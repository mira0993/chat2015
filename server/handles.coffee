MAX_TRIES = 5

get_common_params = (params) ->
	resp =
		"db": params.db
		"srv": params.srv
		"clt": params.clt
		"request_uuid": params.data.request_uuid
		"type": params.data.type
	return resp

get_actual_dt_string = () ->
	return (new Date).toISOString()

send_response = (params) ->
	store_in_db = () ->
		stmt = params.db.prepare('insert into acks values(?)')
		stmt.run(params.request_uuid, (err) ->
			if err
				setTimeout(store_in_db, 500)
			else
				params.resp.response_uuid = params.request_uuid
				params.resp.type = params.type
				resp = JSON.stringify(params.resp)
				cycle_send = (err) ->
					if err
						params.srv.send(resp, 0, resp.length, params.clt.port,
							params.clt.address, cycle_send)
					else
						watchdog(params)
				cycle_send(true)
		)
	store_in_db()

send_error = (params) ->
	params.resp = {'response': "#{params.err}"}
	send_response(params)

watchdog = (params) ->
	timeout = 1000
	times = 0
	cycle = () ->
		params.db.get('select uuid from acks where uuid = ?',
			params.resp.response_uuid,
			(err, row) ->
				if err
					console.log('ERROR: That acknowledgement doesn\'t exist')
				else if row
					resp = JSON.stringify(params.resp)
					params.srv.send(resp, 0, resp.length, params.clt.port,
						params.clt.address)
					times++
					if times <= MAX_TRIES
						setTimeout(cycle, timeout)
		)
	setTimeout(cycle, timeout)

module.exports.block_user = (params) ->
	resp = get_common_params(params)
	stmt = params.db.prepare('''insert into blacklist values (?, ?)''')
	stmt.run(params.data.blocker, params.data.blocked, (err) ->
		if err
			resp.err = err
			send_error(resp)
		else
			resp.resp = {'response': 'OK'}
			send_response(resp)
	)

module.exports.connect_user = (params) ->
	resp = get_common_params(params)
	create_session = (id) ->
		stmt = params.db.prepare('''insert into sessions
			(id, ip_address, port) values (?, ?, ?)''')
		stmt.run(id, params.clt.address, params.clt.port,
			(err) ->
				if err
					resp.err = err
					send_error(resp)
				else
					resp.resp = {'response': 'OK', 'username_id': id}
					send_response(resp)
		)

	create_inbox = (id) ->
		params.db.run("""create table if not exists messages_#{id}(
			id integer primary key autoincrement,
			sender integer,
			dtime text,
			message text,
			foreign key (sender) references users(id))""",
			(err) ->
				if err
					resp.err = err
					send_error(resp)
				else
					params.db.get('select id from sessions where id = ?', id,
						(err, row) ->
							if row
								resp.resp = 
									'response': 'Already Connected'
									'username_id': id
								send_response(resp)
							else if err
								resp.err = err
								send_error(resp)
							else
								create_session(id)
					)
		)

	# Comprobamos si ya existe el usuario
	params.db.get('select id from users where username = ?', params.data.username,
		(err, row) ->
			if row
				# Si existe pasamos su id actual
				create_inbox(row['id'])
			else if err
				resp.err = err
				send_error(resp)
			else
				# Si no existe lo creamos
				stmt = params.db.prepare('insert into users (username) values (?)')
				stmt.run(params.data.username, (err) ->
					if err
						resp.err = err
						send_error(resp)
					else
						create_inbox(this.lastID)
				)
	)

module.exports.dispatcher = (params) ->
	resp = get_common_params(params)
	resp.resp = {"response": "OK", "messages": new Array()}

	dispatcher_file = () ->
		stmt = params.db.prepare('update files set lock=1 where id = ?')
		params.db.each('''select A.id, A.filename, A.chunks, B.username from files A
			inner join users B on A.sender=B.id
			where A.receiver = ? and A.lock = 0''', params.data.username_id,
			((err, row) ->
				if err
					console.log(err)
				else
					resp.resp.messages.push(
						"type": "file"
						"file_id": row.id
						"username": row.username
						"filename": row.filename
						"chunks": row.chunks)
					stmt.run(row.id, (err) ->
						if err
							console.log(err)
					)
			),
			(err, num_rows) ->
				if err
					console.log(err)
				send_response(resp)
			)
		return

	dispatcher_private = () ->
		stmt = params.db.prepare("""delete from messages_#{params.data.username_id}
			where id = ?""")
		params.db.each("""select A.id, B.username, A.message
			from messages_#{params.data.username_id} A
			inner join users B on A.sender=B.id""",
			((err, row) ->
				if err
					console.log(err)
				else
					resp.resp.messages.push(
						"type": "private"
						"username": row.username
						"text": row.message)
					stmt.run(row.id, (err) ->
						if err
							console.log(err)
					)
			),
			((err, num_rows) ->
				if err
					console.log(err)
				dispatcher_file()
			)
		)
	
	stmt = params.db.prepare('delete from push_public where id = ? and user = ?')
	params.db.each('''select B.id, B.user, C.username, A.message
		from public_messages A
		inner join push_public B on A.id=B.id
		inner join users C on A.sender=C.id
		where B.user = ?''', params.data.username_id,
		((err, row) ->
			if err
				console.log(err)
			else
				resp.resp.messages.push(
					"type": "public"
					"username": row.username
					"text": row.message)
				stmt.run(row.id, row.user, (err) ->
					if err
						console.log(err)
				)
		),
		((err, num_rows) ->
			if err
				console.log(err)
			dispatcher_private()
		)
	)

module.exports.disconnect_user = (params) ->
	resp = get_common_params(params)
	stmt = params.db.prepare('delete from sessions where id = ?')
	stmt.run(params.data.username_id, (err) ->
		if err
			resp.err = err
			send_error(resp)
		else if this.changes == 1
			resp.resp = {'response': 'OK'}
			send_response(resp)
		else
			resp.resp = {'response': 'You weren\'t connected'}
			send_response(resp)
	)

module.exports.list_users = (params) ->
	resp = get_common_params(params)
	common_qry = """select A.id, A.username,
		case when B.id is null then -1 else 0 end as status,
		case when C.blocker is null then 0 else -1 end as blocked
		from users A left outer join sessions B on A.id=B.id
		left outer join blacklist C on A.id=C.blocked and C.blocker = ?"""
	clbk = (err, rows) ->
		resp.resp = if err \
			then {'response': "#{err}"} \
			else {'response': 'OK', 'obj': rows}
		send_response(resp)
	if params.data.filter == ''
		parameters = [common_qry, [params.data.username_id], clbk]
	else
		parameters = ["#{common_qry} where username  like ?",
			[params.data.username_id, "%#{params.data.filter}%"], clbk]
	params.db.all.apply(params.db, parameters)

module.exports.private_message = (params) ->
	resp = get_common_params(params)
	success_resp = () ->
		resp.resp = {"response": "OK"}
		send_response(resp)

	save_private = () ->
		stmt = params.db.prepare("""insert into
			messages_#{params.data.receiver_id} (sender, dtime, message)
			values (?, ?, ?)""")
		stmt.run(params.data.username_id, get_actual_dt_string(), params.data.message,
			(err) ->
				if err
					resp.err = err
					send_error(resp)
		)

	params.db.get('select blocked from blacklist where blocker = ? and blocked = ?',
		params.data.receiver_id, params.data.username_id,
		(err, row) ->
			if (not err) and (not row)
				save_private()
			else
				console.log("Blocker = #{params.data.receiver_id} -"
					"Blocked = #{params.data.username_id}")
			success_resp()
	)
	

module.exports.public_message = (params) ->
	resp = get_common_params(params)
	store_public = (id) ->
		stmt = params.db.prepare("""insert into push_public
			values(#{id}, ?)""")
		params.db.each('''select A.id,
			case when B.blocker is null then 0 else 1 end as permission
			from users A left outer join blacklist B on A.id=B.blocker
			where A.id != ?''',
			params.data.username_id,
			((err, row) ->
				if err
					console.log(err)
				else if row
					if row.permission == 1
						console.log("Blocker = #{row.id} -"
							"Blocked = #{params.data.username_id}")
					else
						stmt.run(row.id, (err) ->
							if err
								console.log(err)
						)
			),
			((err, num_rows) ->
				if err
					console.log(err)
			)
		)

	stmt = params.db.prepare('''insert into public_messages
		(sender, dtime, message) values (?, ?, ?)''')
	stmt.run(params.data.username_id, get_actual_dt_string(), params.data.message,
		(err) ->
			if err
				resp.err = err
				send_error(resp)
			else
				resp.resp = {'response': 'OK'}
				send_response(resp)
				store_public(this.lastID)
	)

module.exports.receive_ack = (params) ->
	resp = get_common_params(params)
	stmt = params.db.prepare('''delete from acks where uuid = ?''')
	stmt.run(params.data.ack_uuid, (err) ->
		if(err)
			console.log(err)
	)

module.exports.receive_file = (params) ->
	resp = get_common_params(params)
	stmt = params.db.prepare('''insert into files
		(filename, chunks, lock, transferred, sender, receiver)
		values (?, ?, 0, 0, ?, ?)''')
	stmt.run(params.data.filename, params.data.chunks, params.data.sender,
		params.data.receiver,
		((err) ->
			if err
				resp.err = err
				send_error(resp)
			else
				resp.resp = {'response': 'OK', 'file_id': this.lastID}
				send_response(resp)
		)
	)

module.exports.save_chunk = (params) ->
	resp = get_common_params(params)
	save_finished = () ->
		stmt = params.db.prepare('update files set transferred=1 where id = ?')
		stmt.run(params.data.file_id, (err) ->
			if err
				console.log(err)
		)

	stmt = params.db.prepare('''insert into chunks
		(file, chunk_order, content) values (?, ?, ?)''')
	stmt.run(params.data.file_id, params.data.order, params.data.content,
		(err) ->
			if err
				resp.err = err
				send_error(resp)
			else
				resp.resp = {'response': 'OK'}
				send_response(resp)
				params.db.get('''select case when count(B.id) = A.chunks
					then 0 else 1 end as finished
					from files A inner join chunks B on A.id=B.file''',
					(err, row) ->
						if row.finished == 0
							save_finished()
				)
	)

module.exports.send_chunk = (params) ->
	resp = get_common_params(params)
	stmt = params.db.prepare('delete from chunks where id = ?')
	params.db.get('''select B.id, B.content from files A
		inner join chunks B on A.id=B.file
		where A.id = ? and A.lock = 1 and B.chunk_order = ?''',
		params.data.file_id, params.data.num_part, (err, row) ->
			if err
				resp.err = err
				send_error(resp)
			else
				resp.resp = {'response': 'OK', 'content': row.content}
				send_response(resp)
				stmt.run(row.id, (err) ->
					if err
						console.log(err)
				)
	)

module.exports.unblock_user = (params) ->
	resp = get_common_params(params)
	stmt = params.db.prepare('''delete from blacklist
		where blocker = ? and blocked = ?''')
	stmt.run(params.data.blocker, params.data.blocked, (err) ->
		if err
			resp.err = err
			send_error(resp)
		else
			resp.resp = {'response': 'OK'}
			send_response(resp)
	)