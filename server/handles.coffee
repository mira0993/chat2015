MAX_TRIES = 5

extend = require('extend')

get_actual_dt_string = () ->
	return (new Date).toISOString()

send_response = (params) ->
	#omit_arr = ['Push', 'List', 'Cam', 'R_Chunk', 'S_Chunk', 'File']
	omit_arr = ['List', 'Cam', 'R_Chunk', 'S_Chunk', 'File']
	sender = () ->
		params.resp.response_uuid = params.data.request_uuid
		params.resp.type = params.data.type
		resp = new Buffer(JSON.stringify(params.resp))
		cycle_send = (err) ->
			if err
				srv.send(resp, 0, resp.length, params.clt.port,
					params.clt.address, cycle_send)
			else
				watchdog(params)
		cycle_send(true)

	store_in_db = () ->
		stmt = db.prepare('insert into acks values(?)')
		stmt.run(params.data.request_uuid, (err) ->
			if err
				setTimeout(store_in_db, 500)
			else if omit_arr.indexOf(params.data.type) == -1
				flag_log = true
				if params.data.type == "Push" and params.resp.messages.length == 0
					flag_log = false
				if flag_log
					db.get('select id from logs order by id desc limit 1',
						(err, row) ->
							log_id = 1
							if row
								log_id = row.id + 1
							stmt = db.prepare('insert into logs values (?, ?)')
							stmt.run(log_id, JSON.stringify(params.data), (err) ->
								if err
									w.error(err)
								else
									w.debug('Storing %d', log_id)
								sender()
							)
					)
				else
					sender()
			else
				sender()
		)
	if params.clt.port == -1
		module.exports.replicator_dequeue()
	else
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
					resp = new Buffer(JSON.stringify(params.resp))
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
		db.get("""select name from sqlite_master where type='table' and
			name='messages_#{params.data.username_id}'""", (err, row) ->
				if row
					stmt = db.prepare("""delete from
						messages_#{params.data.username_id} where id = ?""")
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
			setTimeout((()->
				if global.send_time_obj != null
					clearTimeout(global.send_time_obj)
					global.send_master_time()), 5000)
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
				w.debug('Sending ack public')
				json = {'message': params.data.message, 'is_mine': true}
				db.get('select username from users where id = ?',
					params.data.username_id,
					(err, row) ->
						if err
							w.debug(err)
						else if row
							w.debug('Sending broadcast')
							json.username = row.username
							message = new Buffer(JSON.stringify(json))
							srv_external.send(message, 0, message.length, EXTERNAL_PORT, MULTICAST_HOST)
				)
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
				params.resp = {'response': 'OK', 'file_uuid': params.data.file_uuid, 'fn':params.data.filename}
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

module.exports.init_cam = (params) ->
	db.get('select ip_address, port from sessions where id = ?',
		params.data.receiver_id,
		(err, row) ->
			if err
				params.err = err
				send_error(params)
			else if not row
				params.err = 'That user isn\'t connected'
				send_error(params)
			else
				params.resp = 
					'response': 'OK'
					'ip_address': row.ip_address
				send_response(params)
				new_params = new Object()
				extend(true, new_params, params)
				new_params.resp.username_id = params.data.username_id
				new_params.resp.ip_address = params.clt.address
				new_params.clt.address = row.ip_address
				new_params.clt.port = row.port
				w.debug('Sending')
				w.debug(new_params)
				send_response(new_params)
	)
	return

module.exports.replicator_dequeue = () ->
	if rdequeue.length == 0
		setTimeout(module.exports.replicator_dequeue, 1000)
	else
		params = rdequeue.shift()
		handle_incoming(params.json, params.clt)