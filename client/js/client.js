var dgram = require('dgram');
var sqlite3 = require("sqlite3");
var PORT=8000;
var HOST=['192', '168', '1', '72'];
var SERVER= '';
var MULTICAST_HOST = [HOST[0], HOST[1], HOST[2], '255'].join('.')
var MULTICAST_PORT = 5555;
var received_ip = false
var clock_adjustment = 0

var db = new sqlite3.Database(':memory:');

if (gui.App.argv.indexOf('-s') >= 0)
    child_server = cp.fork('', {execPath: 'coffee', execArgv: ['../server/server.coffee']});

if (child_server) {
    child_server.on('message', function (m) {
        if (m.server_ip){
            SERVER = m.server_ip;
            received_master = true;
            wlog.info("server_ip: "+ m.server_ip);
        }
        else if (m.adjustment != undefined){
            clock_adjustment = m.adjustment
        }
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
};


var handle_messages = function (message, remote) {
    var data = JSON.parse(message.toString('utf-8'));
    if (data.type) {
        if (data.response) {
            receive(data);
        }
    }
};


me.on('listening', function() {
    addr = me.address();
    wlog.info("Listening on " + addr.address + ":" + addr.port);
});

me.on('message', handle_messages);

create_db();
me.bind();





