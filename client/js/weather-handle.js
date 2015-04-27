/**
 * Created by ines on 4/25/15.
 */

// Docs at http://simpleweatherjs.com



var loadWeather = function(location, woeid){
    $.simpleWeather({
        location: location,
        woeid: woeid,
        unit: 'c',
        success: function(weather) {
            html =  '<div class="row"><div class="col-md-4" '+
                    'style="height:120px"><h2><i class="icon-'+weather.code +
                    '"></i></h2></div><div class="col-md-4" '+
                    'style="height:60px"><h2>'+weather.temp+
                    '&deg;'+weather.units.temp+'</h2></div>'+
                    '<div class="col-md-4" style="height:90px"><ul><li>'+
                    weather.city+', '+weather.region+'</li><li '+
                    'class="currently">'+weather.currently+
                    '</li><li>'+weather.wind.direction+' '+weather.wind.speed+
                    ' '+weather.units.speed+'</li></ul></div></div>';
                    $("#weather").html(html);
        },
        error: function(error) {
            $("#weather").html('<p>'+error+'</p>');
        }
    });
}

$(document).ready(function() {
    loadWeather('Guadalajara', '');
    setInterval(function() { loadWeather('Guadalajara', '') }, 600000);

//    loadWeather('Guadalajara', '');
    //if ("geolocation" in navigator){
    //    navigator.geolocation.getCurrentPosition(function(position) {
    //        loadWeather(position.coords.latitude+','+position.coords.longitude);
    //    });
    //}else{
    //    loadWeather('Guadalajara', '');
    //}

});


