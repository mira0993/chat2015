dgram = require('dgram')
sqlite3 = require('sqlite3')
hdl = require('./handles')

PORT = 8000
HOST = '127.0.0.1'
srv = dgram.createSocket('udp4')
db = new sqlite3.Database(':memory:')
#db = new sqlite3.Database('test.db')

create_db = () ->
	db.run('''create table if not exists users(
		id integer primary key autoincrement,
		username text unique)''')
	db.run('''create table if not exists sessions(
		id integer primary key,
		ip_address text,
		port integer,
		foreign key (id) references users (id))''')
	db.run('''create table if not exists public_messages(
		id integer primary key autoincrement,
		sender integer,
		dtime text,
		message text,
		foreign key (sender) references users (id))''')
	db.run('''create table if not exists push_public(
		id integer,
		user integer,
		primary key (id, user),
		foreign key (id) references public_messages (id),
		foreign key (user) references users (id))''')
	db.run('''create table if not exists acks(
		uuid text unique)''')
	db.run('''create table if not exists files(
		id integer primary key autoincrement,
		filename text,
		chunks integer,
		lock integer,
		transferred integer,
		sender integer,
		receiver integer,
		foreign key (sender) references users (id),
		foreign key (receiver) references users (id))''')
	db.run('''create table if not exists chunks(
		id integer primary key autoincrement,
		file integer,
		chunk_order integer,
		content text,
		foreign key (file) references files (id))''')
	db.run('''create table if not exists blacklist(
		blocker integer,
		blocked integer,
		foreign key (blocker) references users (id),
		foreign key (blocked) references users (id),
		primary key (blocker, blocked))''')

handle_incoming = (msg, clt) ->
	console.log(msg);
	params = 
		"db": db 
		"srv": srv
		"clt": clt
		"data": JSON.parse(msg.toString('utf-8'))
	switch params.data.type
		when 'ACK' then hdl.receive_ack(params)
		when 'Push' then hdl.dispatcher(params)
		when 'Public_Message' then hdl.public_message(params)
		when 'Private_Message' then hdl.private_message(params)
		when 'List' then hdl.list_users(params)
		when 'S_Chunk' then hdl.save_chunk(params)
		when "R_Chunk" then hdl.send_chunk(params)
		when 'File' then hdl.receive_file(params)
		when 'Connect' then hdl.connect_user(params)
		when 'Disconnect' then hdl.disconnect_user(params)
		when 'Block' then hdl.block_user(params)
		when 'Unblock' then hdl.unblock_user(params)

srv.on('listening', () ->
	addr = srv.address()
	console.log("Listening on #{addr.address}:#{addr.port}"))

srv.on('message', handle_incoming)

create_db()
srv.bind(PORT, HOST)