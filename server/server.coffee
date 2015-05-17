dgram = require('dgram')
cluster = require('cluster')
cp = require('child_process')
sqlite3 = require('sqlite3')
global.w = require('winston')
hdl = require('./handles')
external = require('./external')

PORT = 8000
HOST = '0.0.0.0'
global.MULTICAST_HOST = '255.255.255.255'
global.iAmMaster = true
global.srv = dgram.createSocket('udp4')
global.EXTERNAL_PORT = 3333
global.srv_external = dgram.createSocket('udp4')
global.db = new sqlite3.Database(':memory:')
#db = new sqlite3.Database('test.db')

DEBUG_EXTERNAL = true

logger_options =
	colorize: true
	prettyPrint: true
	level: 'debug'

w.remove(w.transports.Console);
w.add(w.transports.Console, logger_options)

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
		uuid text,
		filename text,
		chunks integer,
		lock integer,
		transferred integer,
		sender integer,
		receiver integer,
		foreign key (sender) references users (id),
		foreign key (receiver) references users (id))''')
	db.run('''create table if not exists chunks(
		file text,
		chunk_order integer,
		content text,
		foreign key (file) references files (uuid))''')
	db.run('''create table if not exists blacklist(
		blocker integer,
		blocked integer,
		foreign key (blocker) references users (id),
		foreign key (blocked) references users (id),
		primary key (blocker, blocked))''')

handle_incoming = (msg, clt) ->
	params = 
		"clt": clt
		"data": JSON.parse(msg.toString('utf-8'))
	if params.data.type
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
			when 'Cam' then hdl.init_cam(params)
	else
		# Cuando es broadcast
		if params.data.who_is_the_master and iAmMaster
			w.debug('Here i am')
			resp = new Buffer(JSON.stringify({'i_am': true}))
			srv.send(resp, 0, resp.length, clt.port, clt.address)

if cluster.isMaster
	process.on('message', (msg) ->
		# Aqui podemos leer los mensajes que nos envie el cliente
		# process.send('Hi parent') # Aqui podemos mandarle mensajes al cliente
	)

	srv_external.on('message', (msg, clt) ->
		#w.debug(msg)
		data = JSON.parse(msg.toString('utf-8'))
		w.debug(data)
		if not data.is_mine
			external.handle_new_messages(data)
	)

	srv_external.on('listening', () ->
		addr = srv_external.address()
		srv_external.setBroadcast(true)
		###
		setTimeout(() ->
			srv_external.setBroadcast(true)
			message = new Buffer(JSON.stringify({'message': 'Hola, como estas?', 'username': 'Cristian'}))
			srv_external.send(message, 0, message.length, EXTERNAL_PORT, MULTICAST_HOST, (err) ->
				if err
					w.error(err)
			)
		, 4000)
		###
		console.log("Listening on #{addr.address}:#{addr.port}")
	)

	srv.on('listening', () ->
		addr = srv.address()
		###
		setTimeout(() ->
			srv.setBroadcast(true);
			message = new Buffer(JSON.stringify({'who_is_the_master': true}))
			srv.send(message, 0, message.length, PORT, MULTICAST_HOST, (err) ->
				if err
					w.debug(err)
			)
		, 1000)
		###
		console.log("Listening on #{addr.address}:#{addr.port}"))

	srv.on('message', handle_incoming)

	create_db()
	srv.bind(PORT, HOST)
	if DEBUG_EXTERNAL
		srv_external.bind(EXTERNAL_PORT, HOST)

	# Aqui se crea el primer hijo 
	global.replicator = cluster.fork()
else
	repl = require('./replicator')
	process.on('message', (msg) ->
		repl.handle(msg);
	)