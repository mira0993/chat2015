/**
 * Created by ines on 4/26/15.
 */
module.exports.PORT=8000;
module.exports.SERVER="127.0.0.1";

module.exports.CONNECT = 1;
PRIVATE = 2;
PUBLIC = 3;


var uuid = require('uuid')

send_response = function(me, json){
    msg = JSON.stringify(json);
    me.send(new Buffer(msg),0, msg.length,module.exports.PORT,
            module.exports.SERVER, function(err, bytes){
        if(err){
            throw err;
            process.exit(1);
        }else{
            console.log("send_message");
            return watchdog();
        }
    });
};

module.exports.__connect__ = function(me, db, user){
    var id = uuid.v1();
    var json = {"type":"Connect",
                "request_uuid": id,
                "username": user
    };
    var stmt = db.prepare("INSERT INTO acks (uuid, type) VALUES (?,?)");
    stmt.run(id, "Connect", function(err){
        if(err){
            console.log("ERROR SAVING UUID");
            return watchdog();
        }else{
            return send_response(me, json);
        }
    });


};

var watchdog = function(){
    setInterval(watchdog, 1000);;
}

module.exports.recv_ack = function(db, json){
    var callback = function(err, row){
        console.log("select");
        if(row){
            console.log(row);
            db.run('delete from acks where uuid = ?', json["response_uuid"],
                function (err){
                    if(err){
                        console.log("ERROR DELETE ACK");
                        callback();
                    }else{
                        console.log("DONE DELETE");
                        return watchdog();
                    }

                });
        }
    }
    db.get('select uuid from acks where uuid = ?', json["response_uuid"],
            callback);
    console.log("ines");
};

