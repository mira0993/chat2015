get_actual_dt_string = () ->
	return (new Date).toISOString()

send_response = (db, srv, json, clt) ->
	store_in_db = () ->
		stmt = db.prepare('''insert into acks (received) values(0)''')
		stmt.run((err) ->
			if err
				setTimeout(store_in_db, 500)
			else
				json.response_id = this.lastID
				resp = JSON.stringify(json)
				cycle_send = (err) ->
					if err
						srv.send(resp, 0, resp.length, clt.port, clt.address,
							cycle_send)
					else
						watchdog(db, srv, json, clt)
				cycle_send(true)
		)
	store_in_db()

send_error = (db, srv, clt, err) ->
	resp = {'response': "#{err}"}
	send_response(db, srv, resp, clt)

watchdog = (db, srv, json, clt) ->
	timeout = 1000
	cycle = () ->
		db.get('select id from acks where id = ?', json.response_id,
			(err, row) ->
				if err or (not row)
					console.log('ERROR: That acknowledgement doesn\'t exist')
				else if row.received == 0
					setTimeout(cycle, timeout)
					srv.send(resp, 0, resp.length, clt.port, clt.address)
		)
	setTimeout(cycle, timeout)

module.exports.block_user = (db, srv, data, clt) ->
	stmt = db.prepare('''insert into blacklist values (?, ?)''')
	stmt.run(data.blocker, data.blocked, (err) ->
		if err
			send_error(db, srv, clt, err)
		else
			resp = {'response': 'OK'}
			send_response(db, srv, resp, clt)
	)

module.exports.connect_user = (db, srv, data, clt) ->
	create_session = (id) ->
		stmt = db.prepare('''insert into sessions (id, ip_address, port)
			values (?, ?, ?)''')
		stmt.run(id, clt.address, clt.port,
			(err) ->
				if err
					send_error(db, srv, clt, err)
				else
					resp = {'response': 'OK', 'username_id': id}
					send_response(db, srv, resp, clt)
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
					send_error(db, srv, clt, err)
				else
					db.get('select id from sessions where id = ?', id,
						(err, row) ->
							if row
								resp = 
									'response': 'Already Connected'
									'username_id': id
								send_response(db, srv, resp, clt)
							else if err
								send_error(db, srv, clt, err)
							else
								create_session(id)
					)
		)

	# Comprobamos si ya existe el usuario
	db.get('select id from users where username = ?', data.username,
		(err, row) ->
			if row
				# Si existe pasamos su id actual
				create_inbox(row['id'])
			else if err
				send_error(db, srv, clt, err)
			else
				# Si no existe lo creamos
				stmt = db.prepare('insert into users (username) values (?)')
				stmt.run(data.username, (err) ->
					if err
						send_error(db, srv, clt, err)
					else
						create_inbox(this.lastID)
				)
	)

module.exports.dispatcher = (db, srv, data, clt) ->
	resp = {"response": "OK", "messages": new Array()}

	dispatcher_file = () ->
		stmt = db.prepare('update files set lock=1 where id = ?')
		db.each('''select A.id, A.filename, A.chunks, B.username from files A
			inner join users B on A.sender=B.id
			where A.receiver = ? and A.lock = 0''', data.username_id,
			((err, row) ->
				if err
					console.log(err)
				else
					resp.messages.push(
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
				send_response(db, srv, resp, clt)
			)
		return

	dispatcher_private = () ->
		stmt = db.prepare("""delete from messages_#{data.username_id}
			where id = ?""")
		db.each("""select A.id, B.username, A.message
			from messages_#{data.username_id} A
			inner join users B on A.sender=B.id""",
			((err, row) ->
				if err
					console.log(err)
				else
					resp.messages.push(
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
	
	stmt = db.prepare('delete from push_public where id = ? and user = ?')
	db.each('''select B.id, B.user, C.username, A.message
		from public_messages A
		inner join push_public B on A.id=B.id
		inner join users C on A.sender=C.id
		where B.user = ?''', data.username_id,
		((err, row) ->
			if err
				console.log(err)
			else
				resp.messages.push(
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

module.exports.disconnect_user = (db, srv, data, clt) ->
	stmt = db.prepare('delete from sessions where id = ?')
	stmt.run(data.username_id, (err) ->
		if err
			send_error(db, srv, resp, clt)
		else if this.changes == 1
			resp = {'response': 'OK'}
			send_response(db, srv, resp, clt)
		else
			resp = {'response': 'You weren\'t connected'}
			send_response(db, srv, resp, clt)
	)

module.exports.list_users = (db, srv, data, clt) ->
	common_qry = """select A.username,
		case when B.id is null then -1 else 0 end as status,
		case when C.blocker is null then 0 else -1 end as blocked
		from users A left outer join sessions B on A.id=B.id
		left outer join blacklist C on A.id=C.blocked and C.blocker = ?"""
	clbk = (err, rows) ->
		resp = if err \
			then {'response': "#{err}"} \
			else {'response': 'OK', 'obj': rows}
		send_response(db, srv, resp, clt)
	if data.filter == ''
		params = [common_qry, [data.username_id], clbk]
	else
		params = ["#{common_qry} where username  like ?",
			[data.username_id, "%#{data.filter}%"], clbk]
	db.all.apply(db, params)

module.exports.private_message = (db, srv, data, clt) ->
	success_resp = () ->
		resp = {"response": "OK"}
		send_response(db, srv, resp, clt)

	save_private = () ->
		stmt = db.prepare("""insert into messages_#{data.receiver_id}
			(sender, dtime, message) values (?, ?, ?)""")
		stmt.run(data.username_id, get_actual_dt_string(), data.message,
			(err) ->
				if err
					send_error(db, srv, clt, err)
		)

	db.get('select blocked from blacklist where blocker = ? and blocked = ?',
		data.receiver_id, data.username_id,
		(err, row) ->
			if (not err) and (not row)
				save_private()
			else
				console.log("Blocker = #{data.receiver_id} -"
					"Blocked = #{data.username_id}")
			success_resp()
	)
	

module.exports.public_message = (db, srv, data, clt) ->
	store_public = (id) ->
		stmt = db.prepare("""insert into push_public
			values(#{id}, ?)""")
		db.each('''select A.id,
			case when B.blocker is null then 0 else 1 end as permission
			from users A left outer join blacklist B on A.id=B.blocker
			where A.id != ?''',
			data.username_id,
			((err, row) ->
				if err
					console.log(err)
				else if row
					if row.permission == 1
						console.log("Blocker = #{row.id} -"
							"Blocked = #{data.username_id}")
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

	stmt = db.prepare('''insert into public_messages (sender, dtime, message)
		values (?, ?, ?)''')
	stmt.run(data.username_id, get_actual_dt_string(), data.message,
		(err) ->
			if err
				send_error(db, srv, clt, err)
			else
				resp = {'response': 'OK'}
				send_response(db, srv, resp, clt)
				store_public(this.lastID)
	)

module.exports.receive_ack = (db, srv, data, ctl) ->
	stmt = db.prepare('''update acks set received=1 where id = ?''')
	stmt.run(data.response_id, (err) ->
		if(err)
			console.log(err)
	)

module.exports.receive_file = (db, srv, data, clt) ->
	stmt = db.prepare('''insert into files
		(filename, chunks, lock, transferred, sender, receiver)
		values (?, ?, 0, 0, ?, ?)''')
	stmt.run(data.filename, data.chunks, data.sender, data.receiver, (err) ->
		if err
			send_error(db, srv, clt, err)
		else
			resp = {'response': 'OK', 'file_id': this.lastID}
			send_response(db, srv, resp, clt)
	)

module.exports.save_chunk = (db, srv, data, clt) ->
	save_finished = () ->
		stmt = db.prepare('update files set transferred=1 where id = ?')
		stmt.run(data.file_id, (err) ->
			if err
				console.log(err)
		)

	stmt = db.prepare('''insert into chunks (file, chunk_order, content)
		values (?, ?, ?)''')
	stmt.run(data.file_id, data.order, data.content, (err) ->
		if err
			send_error(db, srv, clt, err)
		else
			resp = {'response': 'OK'}
			send_response(db, srv, resp, clt)
			db.get('''select case when count(B.id) = A.chunks
				then 0 else 1 end as finished
				from files A inner join chunks B on A.id=B.file''',
				(err, row) ->
					if row.finished == 0
						save_finished()
			)
	)

module.exports.send_chunk = (db, srv, data, clt) ->
	stmt = db.prepare('delete from chunks where id = ?')
	db.get('''select B.id, B.content from files A
		inner join chunks B on A.id=B.file
		where A.id = ? and A.lock = 1 and B.chunk_order = ?''', data.file_id,
		data.num_part, (err, row) ->
			if err
				send_error(db, srv, clt, err)
			else
				resp = {'response': 'OK', 'content': row.content}
				send_response(db, srv, resp, clt)
				stmt.run(row.id, (err) ->
					if err
						console.log(err)
				)
	)

module.exports.unblock_user = (db, srv, data, clt) ->
	stmt = db.prepare('''delete from blacklist
		where blocker = ? and blocked = ?''')
	stmt.run(data.blocker, data.blocked, (err) ->
		if err
			send_error(db, srv, clt, err)
		else
			resp = {'response': 'OK'}
			send_response(db, srv, resp, clt)
	)