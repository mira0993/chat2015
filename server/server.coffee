dgram = require('dgram')
cp = require('child_process')
sqlite3 = require('sqlite3')
global.w = require('winston')
hdl = require('./handles')
external = require('./external')

PORT = 9000
HOST = '0.0.0.0'
global.MULTICAST_HOST = '255.255.255.255'
SRV_ID = '-1'

# Master Selection Variables
global.iAmMaster = false
global.init_master_flag = true
global.new_master_flag = false
global.master_ip = ''

global.waiting_for_clock = false
global.timmers = []
global.current_time = Date.now()
global.time_adjustment = 0
global.send_time_obj = null
global.srv = dgram.createSocket('udp4')
global.EXTERNAL_PORT = 3333
global.srv_external = dgram.createSocket('udp4')
global.db = new sqlite3.Database(':memory:')
#global.db = new sqlite3.Database('test.db')

DEBUG_EXTERNAL = true

logger_options =
	colorize: true
	prettyPrint: true
	level: 'error'

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
	db.run('''create table logs(
		id integer primary key,
		data text)''')

send_time_difference = () ->
	w.debug("send_time_difference init func")
	global.waiting_for_clock = false
	sum = 0
	for i in global.timmers
		sum = sum + i.diff
	adjust = sum/(global.timmers.length)
	for i in global.timmers
		tmp = (i.diff * -1) + adjust
		w.debug("tmp "+tmp)
		msg = new Buffer(JSON.stringify({'adjustment': tmp}));
		cycle = () ->
			srv.send(msg, 0, msg.length, PORT, i.addr, (err) ->
				if err
					w.error(err)
					cycle()
				else
					w.debug("sent "+(adjust)+" to "+i.addr)
		)
		cycle()

global.send_master_time = () ->
	w.debug("send_master_time init func")
	global.waiting_for_clock = true
	global.current_time = Date.now();
	global.timmers = []
	global.timmers.push ({"addr":global.master_ip, "diff":0})
	msg = new Buffer(JSON.stringify({'id': SRV_ID, 'time': current_time}));
	srv.send(msg, 0, msg.length, PORT, "255.255.255.255", (err) ->
		if err
			w.error(err)
		else
			setTimeout(send_time_difference,2000)
	)
	global.send_time_obj = setTimeout(global.send_master_time, 30000)

i_am_alive = () ->
	msg = new Buffer(JSON.stringify({'alive': true}))
	srv.send(msg, 0, msg.length, PORT, "255.255.255.255")
	w.debug("still alive")

who_is_master = () ->
	message = new Buffer(JSON.stringify({'who_is_the_master': true}));
	times = 0
	timeout = 500
	global.init_master_flag = false
	cycle = () ->
		srv.setBroadcast(true)
		srv.send(message, 0, message.length, PORT, "255.255.255.255", (err) ->
			if err
				w.error(err)
			else
				w.debug("sent broadcast")
			w.debug(global.init_master_flag)
			setTimeout(() ->
				if global.init_master_flag == false
					times++
					if times <= 2
						cycle()
					else
						global.init_master_flag = true
						global.iAmMaster = true
						setInterval(i_am_alive, 3000)
						process.send({ server_ip: global.master_ip })
						global.send_master_time()
						w.debug("MASTER node...[OK]")
			, timeout)
		)
	cycle()

new_master = () ->
	if SRV_ID <= 0
		w.error("Not valid ID. Cannot send new_master message")
		return
	global.iAmMaster = true
	global.new_master_flag = true
	msg = new Buffer(JSON.stringify({'new_master': SRV_ID}))
	times = 0
	timeout = 1000
	w.debug("new_master: failover attempt")
	cycle = () ->
		srv.send(msg, 0, msg.length, PORT, "255.255.255.255", (err) ->
			if(err)
				w.error(err)
			else
				setTimeout(() ->
					if global.iAmMaster
						times++
						if times <= 2
							cycle()
						else
							global.new_master_flag = false
							process.send({"server_ip": global.master_ip})
							global.send_master_time()
							w.debug("MASTER node...[OK]")
							setInterval(i_am_alive, 3000)
				, timeout)
		)
	cycle()

watch_replicator = (json) ->
	clt = {'address': '', 'port': -1}
	handle_incoming(JSON.stringify(json), clt)

handle_incoming = (msg, clt) ->
	params =
		"clt": clt
		"data": JSON.parse(msg.toString('utf-8'))
	if params.data.type
		if not iAmMaster
			w.warn(params.data)
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
		if params.data.pull_repl
			db.get('select data from logs where id = ?',
				params.data.log_id,
				(err, row) ->
					if err
						w.warn(err)
					else if row
						data = 
							'replication': true
							'id': params.data.log_id
							'data': JSON.parse(row.data)
						message = new Buffer(JSON.stringify(data))
						w.error(data)
						srv.send(message, 0, message.length, clt.port, clt.address)
					else
						w.warn('Not row')
			)
		else if params.data.replication
			stmt = db.prepare('insert into logs values (?, ?)')
			w.warn(params.data.id)
			stmt.run(params.data.log_id,
				JSON.stringify(params.data.data),
				(err) ->
					if err
						w.error(err)
					else
						watch_replicator(params.data.data)
			)
		else if params.data.who_is_the_master
			if iAmMaster
				console.log("other "+clt.address)
				resp = new Buffer(JSON.stringify({'i_am': true}))
				srv.send(resp, 0, resp.length, clt.port, clt.address)
			else
				global.master_ip = clt.address
		else if params.data.i_am
			global.init_master_flag = true
			global.iAmMaster = false
			global.master_ip = clt.address
			global.failover_timeout = setTimeout(new_master,9000);
			process.send({"server_ip": global.master_ip})
			w.debug("STAND_BY node")

		else if params.data.alive
			clearTimeout(global.failover_timeout)
			w.debug("stand_by: restart count")
			global.master_ip = clt.address
			process.send({"server_ip": global.master_ip})
			global.failover_timeout = setTimeout(new_master,9000);

		else if params.data.new_master
			global.master_ip = clt.address
			w.info("I am becoming the new master: node (%s), address (%s)",
				params.data.new_master, clt.address)
			if params.data.new_master > SRV_ID
				global.iAmMaster = false
				global.failover_timeout = setTimeout(new_master,9000);
				process.send({"server_ip": global.master_ip})
				if global.send_time_obj != null
					clearTimeout(global.send_time_obj)
					global.send_time_obj = null
				w.debug("new_server_master_ip: "+ global.master_ip)

		else if params.data.time
			w.debug("received master's time "+params.data.time)
			if params.data.id != SRV_ID
				curr = Date.now()
				resp = new Buffer(JSON.stringify({'diff': curr - params.data.time}))
				srv.send(resp, 0, resp.length, clt.port, clt.address)

		else if params.data.diff
			w.debug("received diff "+params.data.diff)
			if global.waiting_for_clock
				if  Math.abs(params.data.diff) > 18500000
					if params.data.diff < 0
						testing_diff = 18000000
						tmp = {'addr': clt.address, 'diff': (params.data.diff + testing_diff)}
					else
						tmp = {'addr': clt.address, 'diff': (params.data.diff - testing_diff)}
				else
					tmp = {'addr': clt.address, 'diff': params.data.diff}
				global.timmers.push(tmp)

		else if params.data.adjustment != undefined
			w.debug("adjustment "+params.data.adjustment)
			global.time_adjustment = params.data.adjustment
			process.send({adjustment: global.time_adjustment})

		else if params.data.clock_request
			w.debug("clock request")
			if global.send_time_obj != null
				clearTimeout(global.send_time_obj)
				global.send_master_time()

handle_replication = () ->
	if iAmMaster and master_ip != ''
		return
	db.get('select id from logs order by id desc limit 1', (err, row) ->
		log_id = 1
		if row
			log_id = row.id + 1
		data = {'pull_repl': true, 'log_id': log_id}
		w.info(data)
		msg = new Buffer(JSON.stringify(data))
		srv.send(msg, 0, msg.length, PORT, global.master_ip)
	)

# Client communication
process.on('message', (m) ->
	if(m.our_id)
		SRV_ID = m.our_id
		w.debug("server_id: "+ SRV_ID)
		if global.iAmMaster == false
			resp = new Buffer(JSON.stringify({'clock_request': "true"}))
			srv.send(resp, 0, resp.length, PORT, global.master_ip)

)

srv.on('listening', () ->
	setInterval(handle_replication, 1000)
	addr = srv.address()
	console.log("Listening on #{addr.address}:#{addr.port}")
	who_is_master()

	srv_external.on('message', (msg, clt) ->
		data = JSON.parse(msg.toString('utf-8'))
		if not data.is_mine
			external.handle_new_messages(data)
	)
)

srv_external.on('listening', () ->
	addr = srv_external.address()
	srv_external.setBroadcast(true)
	console.log("Listening on #{addr.address}:#{addr.port}")
)

srv.on('message', handle_incoming)
create_db()
srv.bind(PORT, HOST)

if DEBUG_EXTERNAL
	srv_external.bind(EXTERNAL_PORT, HOST)