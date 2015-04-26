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
		id integer primary key autoincrement,
		user integer,
		ip_address text,
		port integer,
		foreign key (user) references users (id))''')
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
		id integer primary key autoincrement,
		received integer)''')
	db.run('''create table if not exists files(
		id integer primary key autoincrement,
		filename text,
		chunks integer,
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

handle_incoming = (msg, clt) ->
	data = JSON.parse(msg.toString('utf-8'))
	switch data.type
		when 'ACK' then hdl.receive_ack(db, srv, data, clt)
		when 'Push' then hdl.dispatcher(db, srv, data, clt)
		when 'Public_Message' then hdl.public_message(db, srv, data, clt)
		when 'Private_Message' then hdl.private_message(db, srv, data, clt)
		when 'Connect' then hdl.connect_user(db, srv, data, clt)
		when 'List' then hdl.list_users(db, srv, data, clt)
		when 'Chunk' then hdl.save_chunk(db, srv, data, clt)
		when 'File' then hdl.receive_file(db, srv, data, clt)

srv.on('listening', () ->
	addr = srv.address()
	console.log("Listening on #{addr.address}:#{addr.port}"))

srv.on('message', handle_incoming)

create_db()
srv.bind(PORT, HOST)