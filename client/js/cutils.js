/**
 * Created by ines on 4/25/15.
 */

var wlog = require('winston')
var video = null;
var my_canvas = null;
var yours_canvas = null;
var is_cam_activated = false;
var cam_tab_id = -1;
var cam_stream = null;
var HOST_CAM = null;
var interval_cam = null;
var child_process_video = null;
var my_context = null;
var yours_context = null;

var logger_options = {'colorize': true, 'prettyPrint': true, level: 'info'}
wlog.remove(wlog.transports.Console);
wlog.add(wlog.transports.Console, logger_options)

navigator.getUserMedia = navigator.getUserMedia || navigator.webkitGetUserMedia || navigator.mozGetUserMedia ||
        navigator.msGetUserMedia || navigator.oGetUserMedia;

function toggle_panel(panel_header, panel_id){

    $("#"+panel_header).toggle(function() {
        $("#"+panel_id).hide();
    }, function() {
        $("#"+panel_id).show();
    });
}


function select_tab(sel_tab){
    sel_index = sel_tab.substr(3);
    if($("#"+sel_tab).length > 0){
        $("#tabs li").each(function (index) {

            if ($(this).attr("class") == "active") {
                $(this).removeClass("active");
            }
            $("#div_" + $(this).attr("id").substr(3)).hide();
        });
        $("#" + sel_tab).addClass("active");
        $("#div_" + sel_index).show();
    }
}


function get_message(id){
    text = $("#sendtext"+id).val();
    files = [];
    $( "#fixed-bar"+id+" > span").each(function(index){
       files.push($(this).attr("title"));
    });
    return {"msg": text, "files":files};
}

function add_message(id, user, text, time, me){
    if(me == true) {
        align = "right";
        bkg_color = "55C1E7";
    }else {
        align = "left";
        bkg_color = "DE4646";
    }
    if(user.length > 0)
        url = "http://placehold.it/50/"+bkg_color+"/fff&text="+user[0].toUpperCase();
    else
        url = "http://placehold.it/50/"+bkg_color+"/fff&text=!";

    msg = '<li class="media" style="margin:0px;">' +
    '<div class="media-body"><div class="media">'+
    '<a class="pull-'+align+'" href="#"><img class="media-object img-circle" '+
    'src="'+url+'"></a>'+
    '<div class="media-body">'+text+'<br> <small class="text-muted">'+user+'| '+
    +time+'</small><hr></div></div></div></li>';
    $("#div_"+id+" div ul").append(msg);
    if($("#tab"+id).attr("class") == "active"){
        $('html, body').animate({
                scrollTop: $(document).height()-$(window).height()},
            0,
            "linear"
        );
    }
    $("#sendtext"+id).val("");
}


function add_message_file(id, user, filename, file_id, time, me){
    wlog.info('Adding file')
    var align = "left";
    var bkg_color = "DE4646";
    var span_file = '';
    if(me == true) {
        align = "right";
        bkg_color = "55C1E7";
        span_file = '<span id="file"'+file_id+' class="glyphicon glyphicon-file" ' +
                    'title="'+filename+'"></span>';
    }else{
        span_file = '<a style="cursor:pointer" onclick=__download__('+file_id+')>' +
        '<span id="file"'+file_id+' class="glyphicon glyphicon-file" ' +
        'title="'+filename+'"></span></a>';
    }
    if(user.length > 0)
        url = "http://placehold.it/50/"+bkg_color+"/fff&text="+user[0].toUpperCase();
    else
        url = "http://placehold.it/50/"+bkg_color+"/fff&text=!";



    msg = '<li class="media" style="margin:0px;">' +
    '<div class="media-body"><div class="media">'+
    '<a class="pull-'+align+'" href="#"><img class="media-object img-circle" '+
    'src="'+url+'"></a>'+
    '<div class="media-body">'+span_file+'&nbsp'+
    filename+'<br> <small class="text-muted">'+user+'| '+
    +time+'</small><hr></div></div></div></li>';
    $("#div_"+id+" div ul").append(msg);
    if($("#tab"+id).attr("class") == "active"){
        $('html, body').animate({
                scrollTop: $(document).height()-$(window).height()},
            0,
            "linear"
        );
    }
    $("#sendtext"+id).val("");
}

function add_user(id, user, connected, blocked){
    var id = Number(id)+1;
    var url = "";
    var blk_icon = UNBLOCKED_COLOR;
    var bkg_color = ICON_D_COLOR;
    var conn = "Disconnected";
    if(blocked == true){
        bkg_color = ICON_B_COLOR;
        blk_icon = BLOCKED_COLOR;
        conn = "Blocked";
    }else {
        if (connected == true) {
            bkg_color = ICON_C_COLOR;
            conn = "Connected";
        }
    }
    if(user.length > 0)
        url = "http://placehold.it/50/"+bkg_color+"/fff&text="+
              user[0].toUpperCase();
    else
        url = "http://placehold.it/50/"+bkg_color+"/fff&text=!";
    html =  '<li id="user'+id+'" class="media"><div class="media-body" '+
            '><div class="media"><a class="pull-left" href="#"><img '+
            'class="media-object img-circle" style="max-height:40px;" '+
            'src="'+url+'" onclick="go_to_chat(\'user'+id+'\')">' +
            '</a><span id="block'+id+'" style="cursor:pointer; ' +
            'font-size:20px;color:'+blk_icon+';"' +
            'class="pull-right glyphicon glyphicon-ban-circle" '+
            'onclick="toogle_block_icon('+id+')"></span>' +
            '<span id="video'+id+'" style="cursor:pointer; ' +
            'font-size:20px;color:#9A9A9A;" ' +
            'class="pull-right glyphicon glyphicon-facetime-video" '+
            'onmouseover="$(this).css(\'color\',\'#DE3939\')" ' +
            'onmouseout="$(this).css(\'color\',\'#9A9A9A\')"' +
            'onclick="go_to_chat(\'user' + id + '\', true)">' +
            '</span><div class="media-body">' +
            '<h5 id="username_"'+
            id+' >'+user+'</h5><small class="text-muted">'+conn+
            '</small></div></div></div></li>';
    $("#clients_panel ul").append(html);
}

function change_user_state(id, connected, blocked){
    var id = Number(id)+1;
    var blk_icon = UNBLOCKED_COLOR;
    var bkg_color = ICON_D_COLOR;
    var conn = "Disconnected";
    if(blocked == true){
        bkg_color = ICON_B_COLOR;
        blk_icon = BLOCKED_COLOR;
        conn = "Blocked";
    }else{
        if(connected == true) {
            bkg_color = ICON_C_COLOR;
            conn = "Connected";
        }
    }

    url = "http://placehold.it/50/"+bkg_color+"/fff&text="+
          $("#user"+id+" img").attr("src").substr(-1);
    $("#user"+id+" img").attr("src", url);
    $("#user"+id+" small").text(conn);
    $("#block"+id).css("color",blk_icon);
}

function toogle_block_icon(html_id){
    if($("#block"+html_id).css("color") == "rgb(204, 242, 246)")
        __un_block__(html_id, "Block");
    else
        __un_block__(html_id, "Unblock");

}

function add_file(id){
    uid = id.substr(4);
    $("#fixed-bar"+uid+" > span").each(function(){
        if($(this).attr("title") == $("#"+id).val())
            return;
    });
    html =  '<span class="btn btn-sml btn-default glyphicon glyphicon-file" '+
            'title="'+$("#"+id).val()+'" onclick="delete_file(event)"></span>';
    $("#fixed-bar"+uid).prepend(html);
    $("#nav"+uid).css("height","85");
}

function delete_file(event){
    domElement =$(event.target);
    parentID = $(domElement).parent().attr("id");
    uid = parentID.substr(9);
    if($("#"+parentID+" > span").length == 1){
        $("#nav"+uid).css("height","50");
    }
    domElement.remove();
}

function delete_file_2(html_id, filename){
    if($("#fixed-bar"+html_id+" > span").length == 1){
        $("#nav"+html_id).css("height","50");
        $("#fixed-bar"+html_id+" span").first().remove();
    }else{
        $("#fixed-bar"+html_id+" > span").each(function(){
            if($(this).attr("title") == filename)
                $(this).remove();
                return;
        });
    }
}

function handle_incomming_video (msg) {
    if (msg.data_url && yours_canvas) {
        var imageObj = new Image();
        imageObj.src = msg.data_url;
        imageObj.onload = function() {
            yours_context.drawImage(this, 0, 0, yours_canvas.width, yours_canvas.height);
        };
    }
}

function add_chat(lid, options){
    id = lid.substr(4);
    user=$("#"+lid+" h5").text();
    new_tab ='<li role="presentation" id="tab'+id+'">'+
            '<a href="#" onclick=\'select_tab("tab'+id+'")\'>'+user+
            '&nbsp&nbsp&nbsp<span id="closetab'+id+'" style="cursor:pointer;'+
            'font-size: 12px; color:#9A9A9A" class="glyphicon ' +
            'glyphicon-remove-sign" ' +
            'onmouseover="$(this).css(\'color\',\'#DE3939\')" ' +
            'onmouseout="$(this).css(\'color\',\'#9A9A9A\')"' +
            'onclick="delete_chat('+id+')"></span>'+
            '</a></li>';

    html='<div id="div_'+id+'" style="display:none"><div class="row" style="padding:5px">'+
        (options.cam
            ?   ('<div style="width:45%; float:left"><ul id="msgs_'+id+'" class="media-list"></ul>'+
                '</div><div style="width:55%; float:right"><div style="margin-top:20px;'+
                'margin-left:auto; margin-right:auto; width:80%; height:200px; background-color:black">'+
                '<video id="mine'+id+'" autoplay="true" style="width:100%; height:100%;"></video><canvas '+
                'id="mine_canvas'+id+'" style="display:none;"></canvas>'+
                '</div><div id="div_canvas_'+id+'" style="margin-top:20px; margin-left:auto; margin-right:auto; width:80%; height:200px;'+
                'background-color:black"><canvas id="yours_canvas'+id+'"></canvas></div>')
            :   '<div style="width:100%"><ul id="msgs_'+id+'" class="media-list"></ul>')+
        '</div><nav id="nav'+id+'" '+
        'class="navbar navbar-fixed-bottom" style="height: 50px">'+
        '<div class="container" style="height: inherit"><div id="fixed-bar'+id+
        '" class="navbar-header" style="height: inherit"><div '+
        'class="input-group" style="height: 50px"><input  id="sendtext'+id+'" '+
        'class="form-control" style="height: 50px" placeholder="Enter Message"'+
        ' type="text"><span class="input-group-btn" style="height: 50px">'+
        '<button class="btn btn-warning btn-file" style="height: 50px">'+
        '<span class="glyphicon glyphicon-file"></span>'+
        '<input id="file'+id+'" type="file" '+
        'onchange=\'add_file($(this).attr("id"))\'></button>'+
        '<button class="btn btn-info" style="height:50px" type="button"'+
        ' id="send'+id+'" onclick="__send_private__('+id+')"><span class="glyphicon glyphicon-arrow-right"></span>'+
        '</button> </span></div></div></div></nav></div></div>';
    $("#main_container").append(html);
    $("#tabs").append(new_tab);
    select_tab("tab"+id);
    if (options.my_cam) {
        cam_tab_id = id;
        video = $("video#mine"+id)[0];
        console.log($("video#mine"+id));
        my_canvas = $("canvas#mine_canvas"+id)[0];
        yours_canvas = $("canvas#yours_canvas"+id)[0];
        yours_canvas.width = $("#div_canvas_"+id)[0].clientWidth;
        yours_canvas.height = $("#div_canvas_"+id)[0].clientHeight;
        my_context = my_canvas.getContext('2d');
        yours_context = yours_canvas.getContext('2d');
        cam_request(id - 1);
        child_process_video.on('message', handle_incomming_video)
    }
}

function delete_chat(html_id){
    if (cam_tab_id == html_id) {
        turn_off_cam();
    }
    $("#tab"+html_id).remove();
    $("#div_"+html_id).remove();
    select_tab("tab0");
}

function go_to_chat(lid, cam){
    var can_request_cam = false;
    if (cam) {
        if (!is_cam_activated) {
            can_request_cam = true;
            is_cam_activated = true;
        }
    }
    var id = lid.substr(4);
    var flag = true;
    $("#tabs li").each(function(){
        wlog.info($(this).attr("id"));
        if($(this).attr("id")== "tab"+id) {
            select_tab("tab" + id);
            flag = false;
        }
    });
    if(flag)
        add_chat(lid, {"cam": can_request_cam, "my_cam": can_request_cam});
}

function turn_off_cam() {
    if (is_cam_activated) {
        clearInterval(interval_cam);
        child_process_video.kill();
        is_cam_activated = false;
        cam_tab_id = -1;
        video.src = "";
        video = null;
        my_canvas = null;
        my_context = null;
        yours_canvas = null;
        yours_context = null;
        cam_stream.stop();
    }
}