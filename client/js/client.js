var dgram = require('dgram');
var sqlite3 = require("sqlite3");
var PORT=8000;
var SERVER=null;
var MULTICAST_HOST = '255.255.255.255'//[HOST[0], HOST[1], HOST[2], '255'].join('.')

var db = new sqlite3.Database(':memory:')
var child_server;
var timeout_server = 400;

if (gui.App.argv.indexOf('-s') >= 0) {
    child_server = cp.fork('', {execPath: 'coffee', execArgv: ['../server/server.coffee']});
    timeout_server = 1000;
}

if (child_server) {
    // child.send('Hi Child!'); // Siempre que quieras enviarle algo al servidor
    child_server.on('message', function (msg) {
      // Cuando quieras leer un mensaje que te haya enviado el servidor
    });
}

var create_db = function () {
    db.run("create table if not exists acks(" +
        "uuid text unique, type text, msg text)")
    db.run("create table if not exists files(" +
        "uuid text, path text, filename text, chunks integer," +
        "sender integer, receiver integer, full_path text)");
    db.run("create table if not exists chunks(" +
        "file text, ch_order integer, content text," +
        "foreign key (file) references files (uuid))");
};

var me = dgram.createSocket('udp4');
var addr = "";

var Connect = function () {
    USERNAME = $("body").attr("name");
    return __connect__();
}


var handle_messages = function (message, remote) {
    var data = JSON.parse(message.toString('utf-8'));
    if (data.type) {
        if (data.response) {
            receive(data);
        }
    } else {
        if (data.i_am) {
            SERVER = remote.address;
            received_master = true;
        } else if (data.is_external) {
            add_message(1, data.username, data.message, "time", false);
        }
    }
};


me.on('listening', function() {
    addr = me.address();
    me.setBroadcast(true);
    var message = new Buffer(JSON.stringify({'who_is_the_master': true}));
    setTimeout(function() {
        wlog.info('Sending broadcast');
        me.send(message, 0, message.length, PORT, MULTICAST_HOST, function (err) {
            if (err)
                wlog.error(err);
        });
        wlog.info("Listening on " + addr.address + ":" + addr.port);
    }, timeout_server);
});

me.on('message', handle_messages);

create_db();
me.bind();





