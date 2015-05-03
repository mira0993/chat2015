dgram = require('dgram');
sqlite3 = require("sqlite3");


db = new sqlite3.Database(':memory:')
var create_db = function () {
    return db.run("create table if not exists acks(" +
                  "uuid text unique, type text, msg text)")
};

var me = dgram.createSocket('udp4');
var addr = "";

var Connect = function () {
    USERNAME = $("body").attr("name");
    return __connect__();
}


var handle_messages = function (message, remote) {
    var data = JSON.parse(message.toString('utf-8'));
    console.log(data);
    if (data.type) {
        if (data.response) {
            receive(data);
        }
    }
};


me.on('listening', function() {
    addr = me.address();
    return console.log("Listening on " + addr.address + ":" + addr.port);
});

me.on('message', handle_messages);

create_db();
me.bind(addr.port, addr.address);





