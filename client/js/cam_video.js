var dgram = require('dgram');
var wlog = require('winston');

var logger_options = {'colorize': true, 'prettyPrint': true, level: 'debug'}
wlog.remove(wlog.transports.Console);
wlog.add(wlog.transports.Console, logger_options)

var once = false;
var UDP_SIZE = 65000;
var PORT = 3555;
var PEER_HOST = process.argv[2];
var srv_send = dgram.createSocket('udp4');
var peer_is_connected = false;
var max_tries = 5;
var global_num_chunks = -1;
var count_chunks = 0;
var array_chunks = new Array();

srv_send.on('listening', function () {
	var i = 0;
	var handle = function () {
		i++;
		data = new Buffer(JSON.stringify({'aya': true}))
		srv_send.send(data, 0, data.length, PORT, PEER_HOST)
		if (i <= max_tries && !peer_is_connected)
			setTimeout(handle, 1000);
	}
	handle();
});

srv_send.bind(PORT)

srv_send.on('message', function (message, clt) {
	var data = JSON.parse(message.toString('utf-8'));
	//wlog.debug(data);
	if (data.iaa)
		peer_is_connected = true;
	else if (data.aya) {
		var msg = new Buffer(JSON.stringify({'iaa': true}))
		srv_send.send(msg, 0, msg.length, PORT, PEER_HOST)
	} else if (data.type) {
		switch (data.type) {
			case "Cam_Header":
				global_num_chunks = data.number_chunks;
				count_chunks = 0;
				break;
			case "Cam_Body":
				array_chunks[data.order] = data.content;
				count_chunks++;
				if (count_chunks == global_num_chunks) {
					var data_url = "";
					for (var i = 0; i < global_num_chunks; i++)
						data_url += array_chunks[i];
					if (data_url.length > 0 && process.connected)
						process.send({"data_url": data_url});
					count_chunks = 0;
					delete array_chunks;
					array_chunks = new Array();
				}
				break;
		}
	}
});

process.on('message', function (msg) {
	if (msg.data_url && peer_is_connected) {
		var trimmed = msg.data_url;
		var chunks = new Array(), message_length = trimmed.length;
	    for (var i = 0; i < message_length; i+=UDP_SIZE) {
	        if ((i + UDP_SIZE) > message_length)
	            chunks.push(trimmed.substring(i, message_length));
	        else
	            chunks.push(trimmed.substring(i, i + UDP_SIZE));
	    }
	    var num_chunks = chunks.length;
	    var cont_handle = function () {
	        for (var i = 0; i < num_chunks; i++) {
	            data = new Buffer(JSON.stringify({"type": "Cam_Body", "order": i, "content": chunks[i]}));
	            srv_send.send(data, 0, data.length, PORT, PEER_HOST)
	        }
	    };
	    if (!once) {
	        once = true;
	        var data = new Buffer(JSON.stringify({"type": "Cam_Header", "number_chunks": num_chunks}));
	        srv_send.send(data, 0, data.length, PORT, PEER_HOST, function (err, bytes) {
	            if (err)
	                console.log(err);
	            else 
	                cont_handle();
	        });
	    } else {
	        cont_handle();
	    }
	}
});