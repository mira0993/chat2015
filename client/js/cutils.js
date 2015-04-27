/**
 * Created by ines on 4/25/15.
 */

function toggle_panel(panel_header, panel_id){

    $("#"+panel_header).toggle(function() {
        $("#"+panel_id).hide();
    }, function() {
        $("#"+panel_id).show();
    });
}


function select_tab(sel_tab){
    sel_index = sel_tab.substr(3);

    $( "#tabs li" ).each(function(index) {

        if($(this).attr("class") == "active") {
            $(this).removeClass("active");
        }
        $("#div_"+$(this).attr("id").substr(3)).hide();
    });
    $("#"+sel_tab).addClass("active");
    $("#div_"+sel_index).show();
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

    msg = '<li class="media"><div class="media-body"><div class="media">'+
    '<a class="pull-'+align+'" href="#"><img class="media-object img-circle" '+
    'src="'+url+'"></a>'+
    '<div class="media-body">'+text+'<br> <small class="text-muted">'+user+'| '+
    +time+'</small><hr></div></div></div></li>';
    $("#div_"+id+" ul").append(msg);
    $('html, body').animate({
            scrollTop: $(document).height()-$(window).height()},
        0,
        "linear"
    );
}

function add_user(id, user, connected){
    if(connected == true) {
        bkg_color = "55C1E7";
        conn = "Connected";
    }else {
        bkg_color = "8A8A8A";
        conn = "Disconnected";
    }
    if(user.length > 0)
        url = "http://placehold.it/50/"+bkg_color+"/fff&text="+
              user[0].toUpperCase();
    else
        url = "http://placehold.it/50/"+bkg_color+"/fff&text=!";

    html =  '<li id="user'+id+'" class="media"><div class="media-body" '+
            'onclick="go_to_chat(\'user'+id+'\')"><div'+
            ' class="media"><a class="pull-left" href="#"><img '+
            'class="media-object img-circle" style="max-height:40px;" '+
            'src="'+url+'"></a><div class="media-body"><h5 id="username_"'+
            id+' >'+user+'</h5><small class="text-muted">'+conn+
            '</small></div></div></div></li>';
        $("#clients_panel ul").append(html);
}

function change_user_state(id, connected){
    if(connected == true) {
        bkg_color = "55C1E7";
        conn = "Connected";
    }else {
        bkg_color = "8A8A8A";
        conn = "Disconnected";
    }
    console.log($("#user"+id+" img").attr("src"));
    url = "http://placehold.it/50/"+bkg_color+"/fff&text="+
          $("#user"+id+" img").attr("src").substr(-1);
    $("#user"+id+" img").attr("src", url);
    $("#user"+id+" small").text(conn);
}

function add_file(id){
    uid = id.substr(4);
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

function add_chat(lid){
    id = lid.substr(4);
    user=$("#"+lid+" h5").text();
    new_tab ='<li role="presentation" id="tab'+id+'">'+
            '<a href="#" onclick=\'select_tab("tab'+id+'")\'>'+user+'</a></li>';

    html='<div id="div_'+id+'" style="display:none"><div class="row" style="padding:5px">'+
        '<ul id="msgs_'+id+'" class="media-list"></ul><nav id="nav'+id+'" '+
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
        ' id="send'+id+'"><span class="glyphicon glyphicon-arrow-right"></span>'+
        '</button> </span></div></div></div></nav></div></div>';
    $("#main_container").append(html);
    $("#tabs").append(new_tab);
    select_tab("tab"+id);
}

function go_to_chat(lid){
    var id = lid.substr(4);
    var flag = true;
    $("#tabs li").each(function(){
        console.log($(this).attr("id"));
        if($(this).attr("id")== "tab"+id) {
            select_tab("tab" + id);
            flag = false;
        }
    });
    if(flag)
        add_chat(lid);

}