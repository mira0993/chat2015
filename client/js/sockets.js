/**
 * Created by ines on 4/26/15.
 */

var MAX_TRIES = 3;
var MAX_LOST = 10000;
var CNT_LOST = 0;

var BLOCKED_COLOR = "#153B58";
var UNBLOCKED_COLOR = "#CCF2F6";
var ICON_C_COLOR = "55C1E6";
var ICON_D_COLOR = "8A8A8B";
var ICON_B_COLOR = "153B60";

var USERNAME_ID = -1;
var USERNAME = "";
var LIST_USERS = {};
var child_server;

var LIST_USER_LOCK = true;
var uuid = require('uuid');
var gui = require('nw.gui');
var win = gui.Window.get();
var cp = require('child_process');
var fs = require('fs');
var path_module = require('path');
        
//------------------------------------------------NODE FUNCTIONS ------------------------------------------------------//

var show_clock = function() {
    function checkTime(i) {
        if (i<10) {i = "0" + i};  // add zero in front of numbers < 10
        return i;
    }
    var millis = Date.now();
    //var millis2 = new Date().getTimezoneOffset()*60*1000;
    var today=new Date();
    //today.setTime(millis +300000+millis2);
    today.setTime(millis + clock_adjustment)
    var h=today.getHours();
    var m=today.getMinutes();
    var s=today.getSeconds();
    m = checkTime(m);
    s = checkTime(s);
    $("#clock_panel").html("<row><h2 style='color:#BDBDBD;font-size:42px;font-weight:200;text-align:center'>"+h+":"+m+":"+s+"</h2></row>");
   // wlog.info(h+":"+m+":"+s);
    setTimeout(function(){show_clock()},500);
};


win.on('close', function() {
    __disconnect__();
    this.hide();                // Pretend to be closed already
    wlog.info("Closing...[OK]");
});

var watchdog = function(uuid){
    var tries = 0;
    var cycle = function(){
        db.get('select * from acks where uuid = ?', uuid,
                function(err, row){
                    if(err){
                        wlog.error('ERROR: That acknowledgement doesn\'t exist');
                    }else if(row){
                        send_response(JSON.parse(row["msg"].toString('utf-8')));
                        tries++;
                        if(tries <= MAX_TRIES)
                            setTimeout(cycle,3000);
                        else {
                            //wlog.warn("LIMIT RETRIES!");
                            CNT_LOST++;
                            if(CNT_LOST > MAX_LOST){
                                wlog.error("LOST SERVER CONNECTION!");
                                win.close(true);
                            }
                        }
                    }
                });
    }
    setTimeout(cycle,1500);

};

var send_response = function(json){
    var arr_discard = ["Cam", "Push", "List"]
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
            if (arr_discard.indexOf(json["type"]) == -1)
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
            wlog.error("ERROR SAVING UUID");
            if (tries < MAX_TRIES) {
                tries++;
                callback();
            }
        }else{
            wlog.debug("saved "+json["request_uuid"]);
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
            _send_header(ret["files"][i], Number(html_id) - 1);
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
    wlog.debug("DOWNLOAD");
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
        win.title = "Chat2015 - "+USERNAME;
        show_clock();
        child_server.send({our_id: USERNAME_ID});
        __list_user__("")
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
    wlog.debug("PUSH");
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
            receive_header(m);
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
                        wlog.error("ERROR DELETE ACK");
                        if(tries < MAX_TRIES) {
                            callback();
                            tries++;
                        }
                    }else{
                        wlog.debug("DONE DELETE");
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
                case 'S_Chunk':
                case "File":
                    send_file(json);
                    //Execute this when you have sent all the chunks in order to
                    // post the file in the conversation window and remove from the send area
                    //add_message_file(Number(om["receiver"])+1, USERNAME,om["filename"],json["file_id"], "time", true);
                    //delete_file_2(Number(om["receiver"])+1, om["filename"]);
                    break;
                case 'R_Chunk':
                    receive_chunk(json);
                    break;
                case "Push":
                    recv_push(json);
                    break;
                case "Disconnect":
                    setTimeout(function(){
                        if (child_server)
                            child_server.kill();
                        win.close(true);}
                        , 4000);
                    break;
                case "Block":
                    var om = JSON.parse(row["msg"].toString('utf-8'));
                    recv_un_block(om, "Block");
                    break;
                case "Unblock":
                    var om = JSON.parse(row["msg"].toString('utf-8'));
                    recv_un_block(om, "Unblock");
                    break;
                case "Cam":
                    child_process_video = cp.fork('',
                        {execPath: 'node', execArgv: ['js/cam_video.js', json.ip_address]});
                    child_process_video.on('message', handle_incomming_video);
                    interval_cam = setInterval(draw, 300);
                    break;
            }
        } else if (json.type == "Cam") {
            send_ack(json);
            if (!is_cam_activated) {
                is_cam_activated = true;
                child_process_video = cp.fork('',
                    {execPath: 'node', execArgv: ['js/cam_video.js', json.ip_address]});
                child_process_video.on('message', handle_incomming_video);
                var html_id = (Number(json["username_id"]) + 1);
                if($("#tab"+html_id).length <=0)
                    add_chat("user"+html_id, {"cam": true, "my_cam": true, "peer_cam": true});
                add_message(html_id, LIST_USERS[json["username_id"]]["username"],
                    "Initializing video", "time", false);
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
    var complete_saving = function (sender, filename) {
        var stream = fs.createWriteStream(filename);
        stream.once('open', function(fd) {
            db.each('select content from chunks where file = ? order by ch_order asc',
                f_uuid, function (err, row) {
                    if (err)
                        wlog.error(err);
                    stream.write(new Buffer(row.content, 'base64'));
                }, function (err, num_rows) {
                    if (err)
                        wlog.error(err);
                    stream.end();
                    if($("#tab"+(sender + 1)).length <=0){
                        add_chat("user"+(sender + 1));
                    }
                    add_message_file(sender + 1,
                        LIST_USERS[sender]["username"],
                        filename, f_uuid,"time", false);
                    wlog.debug(num_rows);
                }
            );
        });
    }
    db.get('select sender, filename from files where uuid = ?', f_uuid, function (err, row) {
        if (err)
            wlog.error(err);
        else if (row)
            complete_saving(row.sender, row.filename);
    })
    
}

/*
    Envía el header del archivo y crea las particiones a ser enviadas
*/
var _send_header = function (full_path, receiver) {
    var path = path_module.basename(full_path);
    var CHUNK_SIZE = 65000;
    var r_uuid = uuid.v4();
    var f_uuid = uuid.v4();
    var cbk_params = new Object();
    fs.readFile(full_path, function (err, data) {
        if (err) {
            w.error(err);
            return;
        }
        var base64data = new Buffer(data).toString('base64');
        var limit = Math.floor(base64data.length / CHUNK_SIZE);
        if (limit < (base64data.length / CHUNK_SIZE))
            limit++;
        cbk_params.chunks = limit;
        cbk_params.count = 0;
        var stmt = db.prepare('insert into files (uuid, path, filename, chunks,' +
            'receiver, full_path) values (?, ?, ?, ?, ?, ?)');
        var r_data = {'type': 'File', 'request_uuid': r_uuid, 'file_uuid': f_uuid,
            'filename': path, 'chunks': limit, 'sender': USERNAME_ID, 'receiver': receiver};
        insert_db(r_data);
        stmt.run(f_uuid, path, path, limit, receiver, full_path, function (err) {
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
    var filename = data.fn;
    var r_uuid = uuid.v4();
    db.get('select ch_order, content from chunks where file = ? order by ch_order limit 1',
        f_uuid,
        function(err, row) {
            if (err)
                error(err);
            else if (row) {
                var r_data = {type: 'S_Chunk', request_uuid: r_uuid, file_uuid: f_uuid,
                    order: row.ch_order, content: row.content};
                insert_db(r_data);
                wlog.info('Sending %s', row.ch_order);
                var stmt = db.prepare('delete from chunks where file = ? and ch_order = ?');
                stmt.run(f_uuid, row.ch_order);
                db.get('select count(*) count from chunks where file = ?', f_uuid,
                    function (err, row) {
                        if (!err && row) {
                            if (row.count == 0) {
                                db.get('select full_path, receiver from files where uuid = ?',
                                    f_uuid, function (err, row) {
                                        if (err)
                                            wlog.error(err);
                                        else if (row){
                                            delete_file_2(row.receiver + 1, row.full_path);
                                            stmt = db.prepare('delete from files where uuid = ?');
                                            stmt.run(f_uuid, function (err) {
                                                if (err)
                                                    error(err);
                                                else
                                                    console.log(data)
                                                    add_message_file(row.receiver + 1, 
                                                        LIST_USERS[row.receiver].username,
                                                        filename, f_uuid,(new Date()).toLocaleTimeString(), true)
                                            });
                                        }
                                    }
                                );
                            }
                        } else {
                            error(err);
                        }
                    }
                );
            }
        }
    );
};

/*
    Envia el siguiente push para recibir otro chunk, esta no es necesario modificarla
    No hay necesidad de mandarla llamar porque ya lo hago yo, solo es funcion auxiliar
 */
var _send_push_chunk = function (f_uuid) {
    wlog.info('Sending next push of file');
    var r_data = {type: 'R_Chunk', request_uuid: uuid.v4(), file_uuid: f_uuid};
    insert_db(r_data);
};

/*
    Recibe el encabezado del archivo, pero ahorita solo lee el primer mensaje
    Hay que pasarle de alguna manera el puro mensaje de archivo o pasarle en 
    que index esta
*/
var receive_header = function (msg) {
    // Necesitas modificar la posición donde esta el mensaje
    var stmt = db.prepare('insert into files (uuid, path, filename, chunks, sender)' +
        ' values(?, ?, ?, ?, ?)');
    wlog.info('Storing file %s', msg.filename);
    stmt.run(msg.file_uuid, msg.filename, msg.filename, msg.chunks, msg.username_id,
        function (err) {
            if (err)
                error(err);
            else {
                // Aqui es la primera llamada al push de chunks despues de recibir el header
                _send_push_chunk(msg.file_uuid);
            }
        }
    );
};

/*
    Deberias mandarla llamar cada vez que se recibe un chunk para que se almacene
    en la base de datos y posteiormente ya se esta mandando llamra para que envie 
    el siguiente push de chunks
*/
var receive_chunk = function (data) {
    wlog.info('Receiving chunk');
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
                        error(err);
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
};

var draw = function (ip_address){
    my_context.drawImage(video, 0, 0, my_canvas.width, my_canvas.height);
    var trimmed = my_canvas.toDataURL("image/jpeg", 1);
    var message = {'data_url': trimmed};
    child_process_video.send(message);
}

var cam_request = function (user_id, peer_cam) {
    if (navigator.getUserMedia) {       
        navigator.getUserMedia({video: true}, function (stream) {
            video.src = window.URL.createObjectURL(stream);
            cam_stream = stream;
            if (peer_cam)
                interval_cam = setInterval(draw, 300);
            else {
                var r_data = {'type': 'Cam', 'request_uuid': uuid.v4(), 'receiver_id': user_id,
                    'username_id': USERNAME_ID};
                insert_db(r_data);
            }
        }, function (e) {
            wlog.warn(e);
        });
    }
}

var receive_cam = function (json) {
    wlog.info(json)
}
