(function() {
    dgram = require('dgram');
    sqlite3 = require("sqlite3");
    sck = require('./js/sockets.js');


    db = new sqlite3.Database(':memory:')
    var create_db = function () {
        return db.run("create table if not exists acks(" +
                      "uuid text unique, type text)")
    };

    var client = dgram.createSocket('udp4');
    address = "";

    Connect = function () {
        return sck.__connect__(client, db, $("body").attr("name"));
    }

    var handle_messages = function (message, remote) {
        var data = JSON.parse(message.toString('utf-8'));
        console.log(data);
        if (data.type) {
            if (data.response) {
                sck.recv_ack(client, db, data);
            } else {
                switch (data["type"]) {
                    case 'Connect':
                        return; //sck.recv_ack(db, data);
                }
            }
        }
    };


    client.on('listening', function() {
        var addr;
        addr = client.address();
        return console.log("Listening on " + addr.address + ":" + addr.port);
    });

    client.on('message', handle_messages);

    create_db();
    client.bind(8001, "127.0.0.1");

}).call(this);