MAX_TRIES = 5

get_actual_dt_string = () ->
	return (new Date).toISOString()

send_response = (params) ->
	store_in_db = () ->
		stmt = db.prepare('insert into acks values(?)')
		stmt.run(params.data.request_uuid, (err) ->
			if err
				setTimeout(store_in_db, 500)
			else
				params.resp.response_uuid = params.data.request_uuid
				params.resp.type = params.data.type
				resp = JSON.stringify(params.resp)
				if params.data.type == 'File'
					w.debug(resp)
				cycle_send = (err) ->
					if err
						srv.send(resp, 0, resp.length, params.clt.port,
							params.clt.address, cycle_send)
					else
						watchdog(params)
				cycle_send(true)
		)
	replicator.send(params)
	store_in_db()

send_error = (params) ->
	params.resp = {'response': "#{params.err}"}
	send_response(params)

watchdog = (params) ->
	timeout = 1000
	times = 0
	cycle = () ->
		db.get('select uuid from acks where uuid = ?',
			params.resp.response_uuid,
			(err, row) ->
				if err
					w.error('ERROR: That acknowledgement doesn\'t exist')
				else if row
					resp = JSON.stringify(params.resp)
					srv.send(resp, 0, resp.length, params.clt.port,
						params.clt.address)
					times++
					if times <= MAX_TRIES
						setTimeout(cycle, timeout)
		)
	setTimeout(cycle, timeout)

module.exports.block_user = (params) ->
	stmt = db.prepare('''insert into blacklist values (?, ?)''')
	stmt.run(params.data.blocker, params.data.blocked, (err) ->
		if err
			params.err = err
			send_error(params)
		else
			params.resp = {'response': 'OK'}
			send_response(params)
	)

module.exports.connect_user = (params) ->
	create_session = (id) ->
		stmt = db.prepare('''insert into sessions
			(id, ip_address, port) values (?, ?, ?)''')
		stmt.run(id, params.clt.address, params.clt.port,
			(err) ->
				if err
					params.err = err
					send_error(params)
				else
					params.resp = {'response': 'OK', 'username_id': id}
					send_response(params)
		)

	create_inbox = (id) ->
		db.run("""create table if not exists messages_#{id}(
			id integer primary key autoincrement,
			sender integer,
			dtime text,
			message text,
			foreign key (sender) references users(id))""",
			(err) ->
				if err
					params.err = err
					send_error(params)
				else
					db.get('select id from sessions where id = ?', id,
						(err, row) ->
							if row
								params.resp = 
									'response': 'Already Connected'
									'username_id': id
								send_response(params)
							else if err
								params.err = err
								send_error(params)
							else
								create_session(id)
					)
		)

	# Comprobamos si ya existe el usuario
	db.get('select id from users where username = ?', params.data.username,
		(err, row) ->
			if row
				# Si existe pasamos su id actual
				create_inbox(row['id'])
			else if err
				params.err = err
				send_error(params)
			else
				# Si no existe lo creamos
				stmt = db.prepare('insert into users (username) values (?)')
				stmt.run(params.data.username, (err) ->
					if err
						params.err = err
						send_error(params)
					else
						create_inbox(this.lastID)
				)
	)

module.exports.dispatcher = (params) ->
	params.resp = {"response": "OK", "messages": new Array()}

	dispatcher_file = () ->
		stmt = db.prepare('update files set lock=1 where uuid = ?')
		db.each('''select A.uuid, A.filename, A.chunks, B.id username_id from files A
			inner join users B on A.sender=B.id
			where A.receiver = ? and A.lock = 0 and transferred = 1''', params.data.username_id,
			((err, row) ->
				if err
					w.error(err)
				else
					params.resp.messages.push(
						"type": "file"
						"file_uuid": row.uuid
						"username_id": row.username_id
						"filename": row.filename
						"chunks": row.chunks)
					stmt.run(row.uuid, (err) ->
						if err
							w.error(err)
					)
			),
			(err, num_rows) ->
				if err
					w.error(err)
				send_response(params)
			)

	dispatcher_private = () ->
		stmt = db.prepare("""delete from messages_#{params.data.username_id}
			where id = ?""")
		db.each("""select A.id, B.id username_id, A.message
			from messages_#{params.data.username_id} A
			inner join users B on A.sender=B.id""",
			((err, row) ->
				if err
					w.error(err)
				else
					params.resp.messages.push(
						"type": "private"
						"username_id": row.username_id
						"text": row.message)
					stmt.run(row.id, (err) ->
						if err
							w.error(err)
					)
			),
			((err, num_rows) ->
				if err
					w.error(err)
				dispatcher_file()
			)
		)
	
	stmt = db.prepare('delete from push_public where id = ? and user = ?')
	db.each('''select B.id, B.user, C.id username_id, A.message
		from public_messages A
		inner join push_public B on A.id=B.id
		inner join users C on A.sender=C.id
		where B.user = ?''', params.data.username_id,
		((err, row) ->
			if err
				w.error(err)
			else
				params.resp.messages.push(
					"type": "public"
					"username_id": row.username_id
					"text": row.message)
				stmt.run(row.id, row.user, (err) ->
					if err
						w.error(err)
				)
		),
		((err, num_rows) ->
			if err
				w.error(err)
			dispatcher_private()
		)
	)

module.exports.disconnect_user = (params) ->
	stmt = db.prepare('delete from sessions where id = ?')
	stmt.run(params.data.username_id, (err) ->
		if err
			params.err = err
			send_error(params)
		else if this.changes == 1
			params.resp = {'response': 'OK'}
			send_response(params)
		else
			params.resp = {'response': 'You weren\'t connected'}
			send_response(params)
	)

module.exports.list_users = (params) ->
	common_qry = """select A.id, A.username,
		case when B.id is null then -1 else 0 end as status,
		case when C.blocker is null then 0 else -1 end as blocked
		from users A left outer join sessions B on A.id=B.id
		left outer join blacklist C on A.id=C.blocked and C.blocker = ?"""
	clbk = (err, rows) ->
		params.resp = if err \
			then {'response': "#{err}"} \
			else {'response': 'OK', 'type':'List', 'obj': rows}
		send_response(params)
	if params.data.filter == ''
		parameters = [common_qry, [params.data.username_id], clbk]
	else
		parameters = ["#{common_qry} where username  like ?",
			[params.data.username_id, "%#{params.data.filter}%"], clbk]
	db.all.apply(db, parameters)

module.exports.private_message = (params) ->
	success_resp = () ->
		params.resp = {"response": "OK"}
		send_response(params)

	save_private = () ->
		stmt = db.prepare("""insert into
			messages_#{params.data.receiver_id} (sender, dtime, message)
			values (?, ?, ?)""")
		stmt.run(params.data.username_id, get_actual_dt_string(), params.data.message,
			(err) ->
				if err
					params.err = err
					send_error(params)
		)

	db.get('select blocked from blacklist where blocker = ? and blocked = ?',
		params.data.receiver_id, params.data.username_id,
		(err, row) ->
			if (not err) and (not row)
				save_private()
			else
				w.debug("Blocker = #{params.data.receiver_id} -"
					"Blocked = #{params.data.username_id}")
			success_resp()
	)
	

module.exports.public_message = (params) ->
	store_public = (id) ->
		stmt = db.prepare("""insert into push_public
			values(#{id}, ?)""")
		db.each('''select A.id, B.blocked
			from users A left outer join blacklist B on A.id=B.blocker
			where A.id != ?''',
			params.data.username_id,
			((err, row) ->
				if err
					w.error(err)
				else if row
					if row.blocked and row.blocked == params.data.username_id
						w.debug("Blocker = #{row.id} -"
							"Blocked = #{params.data.username_id}")
					else
						stmt.run(row.id, (err) ->
							if err
								w.error(err)
						)
			),
			((err, num_rows) ->
				if err
					w.error(err)
			)
		)

	stmt = db.prepare('''insert into public_messages
		(sender, dtime, message) values (?, ?, ?)''')
	stmt.run(params.data.username_id, get_actual_dt_string(), params.data.message,
		(err) ->
			if err
				params.err = err
				send_error(params)
			else
				params.resp = {'response': 'OK'}
				send_response(params)
				store_public(this.lastID)
	)

module.exports.receive_ack = (params) ->
	stmt = db.prepare('''delete from acks where uuid = ?''')
	stmt.run(params.data.ack_uuid, (err) ->
		if(err)
			w.error(err)
	)

module.exports.receive_file = (params) ->
	stmt = db.prepare('''insert into files
		(uuid, filename, chunks, lock, transferred, sender, receiver)
		values (?, ?, ?, 0, 0, ?, ?)''')
	stmt.run(params.data.file_uuid, params.data.filename, params.data.chunks,
		params.data.sender, params.data.receiver,
		((err) ->
			if err
				params.err = err
				send_error(params)
			else
				w.debug('Receiving file %s', params.data.filename)
				params.resp = {'response': 'OK', 'file_uuid': params.data.file_uuid}
				send_response(params)
		)
	)

module.exports.save_chunk = (params) ->
	save_finished = () ->
		stmt = db.prepare('update files set transferred=1 where uuid = ?')
		stmt.run(params.data.file_uuid, (err) ->
			if err
				cw.error(err)
		)

	stmt = db.prepare('''insert into chunks
		(file, chunk_order, content) values (?, ?, ?)''')
	stmt.run(params.data.file_uuid, params.data.order, params.data.content,
		(err) ->
			if err
				params.err = err
				send_error(params)
			else
				w.debug('Receiving %s', params.data.order);
				params.resp =
					'response': 'OK',
					'file_uuid': params.data.file_uuid
				send_response(params)
				db.get('''select case when count(B.file) = A.chunks
					then 0 else 1 end as finished
					from files A inner join chunks B on A.uuid=B.file
					where A.uuid = ?''', params.data.file_uuid,
					(err, row) ->
						if (err)
							w.error(err)
						else if row and row.finished == 0
							save_finished()
				)
	)

module.exports.send_chunk = (params) ->
	stmt = db.prepare('delete from chunks where file = ? and chunk_order = ?')
	db.get('''select B.content, B.chunk_order from files A
		inner join chunks B on A.uuid=B.file where A.uuid = ? and A.lock = 1
		order by chunk_order limit 1''',
		params.data.file_uuid, (err, row) ->
			if err
				params.err = err
				send_error(params)
			else if (row)
				params.resp = 
					'response': 'OK'
					'content': row.content
					'order': row.chunk_order
					'file_uuid': params.data.file_uuid
				send_response(params)
				w.debug('Server: sending response')
				stmt.run(params.data.file_uuid, row.chunk_order, (err) ->
					if err
						w.error(err)
				)
			else
				params.err = 'The file doesn\'t exist.'
				send_error(params)
	)

module.exports.unblock_user = (params) ->
	stmt = db.prepare('''delete from blacklist
		where blocker = ? and blocked = ?''')
	stmt.run(params.data.blocker, params.data.blocked, (err) ->
		if err
			params.err = err
			send_error(params)
		else
			params.resp = {'response': 'OK'}
			send_response(params)
	)