/**
 * Created by ines on 4/26/15.
 */

var PORT=8000;
var SERVER="127.0.0.1";

var MAX_TRIES = 3;
var MAX_LOST = 50;
var CNT_LOST = 0;

var BLOCKED_COLOR = "#153B58";
var UNBLOCKED_COLOR = "#CCF2F6";
var ICON_C_COLOR = "55C1E6";
var ICON_D_COLOR = "8A8A8B";
var ICON_B_COLOR = "153B60";

var USERNAME_ID = -1;
var USERNAME = "";
var LIST_USERS = {};

var LIST_USER_LOCK = true;
var uuid = require('uuid');
var gui = require('nw.gui');
var win = gui.Window.get();
//------------------------------------------------NODE FUNCTIONS ------------------------------------------------------//

win.on('close', function() {
    this.hide();                // Pretend to be closed already
    console.log("Closing...");
    __disconnect__();
});

var watchdog = function(uuid){
    var tries = 0;
    var cycle = function(){
        db.get('select * from acks where uuid = ?', uuid,
                function(err, row){
                    if(err){
                        console.log('ERROR: That acknowledgement doesn\'t exist');
                    }else if(row){
                        send_response(JSON.parse(row["msg"].toString('utf-8')));
                        tries++;
                        if(tries <= MAX_TRIES)
                            setTimeout(cycle,1500);
                        else {
                            console.log("LIMIT RETRIES!");
                            CNT_LOST++;
                            if(CNT_LOST > MAX_LOST){
                                console.log("LOST SERVER CONNECTION!");
                                win.close(true);
                            }
                        }
                    }
                });
    }
    setTimeout(cycle,1500);

};

var send_response = function(json){
    msg = JSON.stringify(json);
    me.send(new Buffer(msg), 0, msg.length, PORT,
            SERVER, function(err, bytes){
        if(err){
            if(json["type"] == "Connect") {
                process.exit(1);
            }else{
                throw err;
            }
        }else{
            return watchdog(json["request_uuid"]);
        }
    });
};

var send_ack = function(json){
    rdata = {"type": "ACK", "ack_uuid": json.response_uuid};
    return send_response(rdata);
};

var insert_db = function(json){
    var tries = 0;
    var callback = function(err){
        if(err){
            console.log("ERROR SAVING UUID");
            if (tries < MAX_TRIES) {
                tries++;
                callback();
            }
        }else{
            console.log("saved "+json["request_uuid"]);
            return send_response(json);
        }
    }
    var stmt = db.prepare("INSERT INTO acks (uuid, type, msg) VALUES (?,?,?)");
    stmt.run(json["request_uuid"], json["type"], JSON.stringify(json), callback);
};


var __connect__ = function(){
    var id = uuid.v1();
    var json = {"type":"Connect",
                "request_uuid": id,
                "username": USERNAME
    };
    insert_db(json);
};

var __disconnect__ = function(){
    var id = uuid.v1();
    var json = {"type": "Disconnect",
                "request_uuid": id,
                "username_id": USERNAME_ID
    }
    insert_db(json);
}


var __list_user__ = function (filter){
    var id = uuid.v1();
    var json = {"type":"List",
                "request_uuid": id,
                "username_id": USERNAME_ID,
                "filter": filter
    };
    insert_db(json);
};

var __send_private__ = function(html_id){
    var ret = get_message(html_id);

    if(ret["msg"] != ""){
        var id = uuid.v1();
        var json = {"type": "Private_Message",
                    "request_uuid": id,
                    "username_id": USERNAME_ID,
                    "receiver_id": (Number(html_id) - 1),
                    "message": ret["msg"]
        };
        insert_db(json);
    }
    //Check if there are files to send
    if(ret["files"].length > 0){
        //Iterate over files that will be sent
        for(var i in ret["files"]){
            var file = ret["files"][i];
            var id = uuid.v1();
            var json = {"type": "File",
                "request_uuid": id,
                "filename": file,  //file = path
                "CHUNKS": 1,    //MI NO SABER
                "sender": USERNAME_ID,
                "receiver": (Number(html_id) - 1)
            };

        }
    }
};

var __send_public__ = function(html_id){
    var ret = get_message(1);

    if(ret["msg"] != ""){
        var id = uuid.v1();
        var json = {"type": "Public_Message",
                    "request_uuid": id,
                    "username_id": USERNAME_ID,
                    "message": ret["msg"]
        };
    }
    insert_db(json);
};

var __push__ = function(){
    if(LIST_USER_LOCK)
        return;
    var id = uuid.v1();
    var json ={"type": "Push",
                "request_uuid": id,
                "username_id": USERNAME_ID
    };
    insert_db(json);
};

var __un_block__ = function(html_id, type){
    var id = uuid.v1();
    var json ={"type": type,
               "request_uuid": id,
               "blocker": USERNAME_ID,
               "blocked": (Number(html_id) - 1)
    };
    insert_db(json);
}

var __download__ = function (file_id){
    console.log("DOWNLOAD");
    //When yo have downloaded it, execute this to open a external window
    //gui.Shell.showItemInFolder('filename');
}

var recv_un_block = function(json, type){
    ans = -1;
    if(type == "Unblock")
        ans = 0;
    var html_id = Number(json["blocked"] - 1);
    LIST_USERS[json["blocked"]]["blocked"] = ans;
    var conn = true;
    var blk = false;
    if (LIST_USERS[json["blocked"]]["status"] != 0)
        conn = false;
    if (LIST_USERS[json["blocked"]]["blocked"] != 0)
        blk = true;
    change_user_state(json["blocked"], conn,blk);
};

var recv_connect = function(json){
    if(json["response"] == "OK") {
        USERNAME_ID = json["username_id"];
        __list_user__("");
        setInterval(function(){__list_user__("")}, 3000);
        setInterval(__push__, 1000);
    }else{
        process.exit(1);
    }
};

var recv_list = function (json){
    if(json["response"] == "OK"){
        for(var i in json["obj"]){
            var u = json["obj"][i];
            if(u["id"] == USERNAME_ID)
                continue;
            var blocked = false;
            if (u["blocked"] != 0)
                blocked = true;
            if(!(u["id"] in LIST_USERS)) {
                if (u["status"] == 0)
                    add_user(u["id"], u["username"], true, blocked);
                else
                    add_user(Number(u["id"]), u["username"], false, blocked);
                LIST_USERS[u["id"]] = u;
            }else{
                if(LIST_USERS[u["id"]]["status"] != u["status"]){
                    if(u["status"] == 0) {
                        change_user_state(u["id"], true, blocked);
                    }else {
                        change_user_state(u["id"], false, blocked);
                    }
                    LIST_USERS[u["id"]]["status"] = u["status"];
                    LIST_USERS[u["id"]]["blocked"] = u["blocked"];
                }
            }
        }
        if(LIST_USER_LOCK)
            LIST_USER_LOCK = false;
    }
};

var recv_push = function(json){
    console.log("PUSH");
    for(var i in json["messages"]){
        var m = json["messages"][i];
        var html_id = (Number(m["username_id"]) + 1);
        if(m["type"] == "private"){
            if($("#tab"+html_id).length <=0){
                add_chat("user"+html_id);
            }
            add_message(html_id,
                        LIST_USERS[m["username_id"]]["username"],
                        m["text"], "time", false);
            if($("#tab"+m["username_id"]).attr("class") != "active")
                $("#tab"+m["username_id"]).attr("color","pink");
        }else if(m["type"] == "public"){
            add_message(1,
                LIST_USERS[m["username_id"]]["username"],
                m["text"], "time", false);
        }else if(m["type"] == "file"){
            console.log("FILE");
            add_message_file(html_id,
                LIST_USERS[m["username_id"]]["username"],
                "filename",m["file_id"],"time", false);
        }
    }
}

var receive = function(json){
    var tries = 0;
    var callback = function(err, row){
        if(row){
            send_ack(json);
            db.run('delete from acks where uuid = ?', json["response_uuid"],
                function (err){
                    if(err){
                        console.log("ERROR DELETE ACK");
                        if(tries < MAX_TRIES) {
                            callback();
                            tries++;
                        }
                    }else{
                        console.log("DONE DELETE");
                    }

                });

            switch(json["type"]){
                case "Connect":
                    recv_connect(json);
                    break;
                case "List":
                    recv_list(json);
                    break;
                case "Private_Message":
                    var om = JSON.parse(row["msg"].toString('utf-8'));
                    add_message(Number(om["receiver_id"])+1,
                                USERNAME, om["message"], "time", true);
                    break;
                case "Public_Message":
                    var om = JSON.parse(row["msg"].toString('utf-8'));
                    add_message(1, USERNAME, om["message"], "time", true);
                    break;
                case "File":
                    var om = JSON.parse(row["msg"].toString('utf-8'));
                    //Execute this when you have sent all the chunks in order to
                    // post the file in the conversation window and remove from the send area
                    //add_message_file(Number(om["receiver"])+1, USERNAME,om["filename"],json["file_id"], "time", true);
                    //delete_file_2(Number(om["receiver"])+1, om["filename"]);
                    break;
                case "Push":
                    recv_push(json);
                    break;
                case "Disconnect":
                    win.close(true);
                    break;
                case "Block":
                    var om = JSON.parse(row["msg"].toString('utf-8'));
                    recv_un_block(om, "Block");
                    break;
                case "Unblock":
                    var om = JSON.parse(row["msg"].toString('utf-8'));
                    recv_un_block(om, "Unblock");
                    break;
            }
        }
    }
    db.get('select * from acks where uuid = ?', json["response_uuid"],
            callback);
};

/*
    Guarda un archivo a partir de un file_uuid pasado como parametro,
    esto una vez que haya recibido completamente el archivo desde el servidor
*/
var _save_file = function (f_uuid) {
    var complete_saving = function (filename) {
        var tmp = '1_' + filename;
        var stream = fs.createWriteStream(tmp);
        stream.once('open', function(fd) {
            db.each('select content from chunks where file = ? order by ch_order asc',
                f_uuid, function (err, row) {
                    if (err)
                        console.log(err);
                    stream.write(new Buffer(row.content, 'base64'));
                }, function (err, num_rows) {
                    if (err)
                        console.log(err);
                    stream.end();
                    console.log(num_rows);
                }
            );
        });
    }
    db.get('select filename from files where uuid = ?', f_uuid, function (err, row) {
        if (err)
            console.log(err);
        else if (row)
            complete_saving(row.filename);
    })
    
}

/*
    Envía el header del archivo y crea las particiones a ser enviadas
*/
var _send_header = function (path, cbk_chunks) {
    var CHUNK_SIZE = 65000;
    var r_uuid = uuid.v4();
    var f_uuid = uuid.v4();
    cbk_params = new Object();
    fs.readFile(path, function (err, data) {
        var base64data = new Buffer(data).toString('base64');
        var limit = Math.floor(base64data.length / CHUNK_SIZE);
        if (limit < (base64data.length / CHUNK_SIZE))
            limit++;
        cbk_params.chunks = limit;
        cbk_params.count = 0;
        var stmt = db.prepare('insert into files values (?, ?, ?, ?)');
        var r_data = {type: 'File', request_uuid: r_uuid, file_uuid: f_uuid,
            filename: path, chunks: limit, sender: user_ids[0], receiver: user_ids[1]};
        send_response(r_data);
        stmt.run(f_uuid, path, path, limit, function (err) {
            if (!err) {
                stmt = db.prepare('insert into chunks values (?, ?, ?)');
                var store_chunk = function (i) {
                    var init = i * CHUNK_SIZE;
                    var end = init + CHUNK_SIZE;
                    if (end > base64data.length)
                        end = base64data.length;
                    stmt.run(f_uuid, i,
                        base64data.substring(init, end),
                        function (err) {
                            if (err)
                                error(err);
                            else if (i < (limit - 1))
                                store_chunk(i + 1);
                            else if (i == limit)
                                cbk_chunks();
                        });
                }
                store_chunk(0);
            }
        });
    });
}

/*
    Cada vez que recibas el response de que un chunk ya se envio deberias
    mandar llamar esta funcion pasandole el json, porque va a tomar cual fue el
    que se envio y proceder a enviar el siguiente
*/
var send_file = function (data) {
    var f_uuid = data.file_uuid;
    var r_uuid = uuid.v4();
    if (cbk_params.count < cbk_params.chunks) {
        db.get('select ch_order, content from chunks where file = ? order by ch_order limit 1',
            f_uuid,
            function(err, row) {
                if (err)
                    error(err);
                else if (row) {
                    var r_data = {type: 'S_Chunk', request_uuid: r_uuid, file_uuid: f_uuid,
                        order: row.ch_order, content: row.content};
                    send_response(r_data);
                    var stmt = db.prepare('delete from chunks where file = ? and ch_order = ?');
                    stmt.run(f_uuid, row.ch_order);
                    db.get('select count(*) count from chunks where file = ?', f_uuid,
                        function (err, row) {
                            if (!err && row) {
                                if (row.count == 0) {
                                    stmt = db.prepare('delete from files where uuid = ?');
                                    stmt.run(f_uuid, function (err) {
                                        if (err)
                                            error(err);
                                        else
                                            return; // Aqui ya termino
                                    });
                                }
                            } else {
                                error(err);
                            }
                        }
                    );
                }
            });
    }
    cbk_params.count++;
}

/*
    Envia el siguiente push para recibir otro chunk, esta no es necesario modificarla
    No hay necesidad de mandarla llamar porque ya lo hago yo, solo es funcion auxiliar
 */
var _send_push_chunk = function (f_uuid) {
    var r_data = {type: 'R_Chunk', request_uuid: uuid.v4(), file_uuid: f_uuid};
    send_response(r_data);
}

/*
    Recibe el encabezado del archivo, pero ahorita solo lee el primer mensaje
    Hay que pasarle de alguna manera el puro mensaje de archivo o pasarle en 
    que index esta
*/
var receive_header = function (data) {
    if (data.messages && data.messages.length > 0) {
        // Necesitas modificar la posición donde esta el mensaje
        var msg = data.messages[0];
        var stmt = db.prepare('insert into files values(?, ?, ?, ?)');
        stmt.run(msg.file_uuid, msg.filename, msg.filename, msg.chunks,
            function (err) {
                if (err)
                    error(err);
                else {
                    // Aqui es la primera llamada al push de chunks despues de recibir el header
                    _send_push_chunk(msg.file_uuid);
                }
            }
        );
    }
}

/*
    Deberias mandarla llamar cada vez que se recibe un chunk para que se almacene
    en la base de datos y posteiormente ya se esta mandando llamra para que envie 
    el siguiente push de chunks
*/
var receive_chunk = function (data) {
    if (!data.file_uuid)
        return;
    var stmt = db.prepare('insert into chunks values(?, ?, ?)');
    stmt.run(data.file_uuid, data.order, data.content, function (err) {
        if (err)
            error(err);
        else {
            db.get('select case when count(B.ch_order) == A.chunks then 0 else 1 end as finished ' +
                'from files A inner join chunks B on A.uuid=B.file where A.uuid = ?', data.file_uuid,
                function (err, row) {
                    if (err)
                        error(err)
                    else if (row) {
                        // Una vez descargado ya se esta mandando llamar el save
                        if (row.finished == 0)
                            _save_file(data.file_uuid);
                        else
                            _send_push_chunk(data.file_uuid);
                    }
                }
            );
        }
    });
}