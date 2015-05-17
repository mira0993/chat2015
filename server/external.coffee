module.exports.handle_new_messages = (data) ->
	data.is_external = true;
	message = new Buffer(JSON.stringify(data))
	db.each('select ip_address, port from sessions',
		(err, row) ->
			if row
				srv.send(message, 0, message.length, row.port, row.ip_address)
	)