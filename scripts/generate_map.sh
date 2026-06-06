#!/usr/bin/env bash
# Arkansas AllStar node map: live status, county overlay, last-keyed activity, 65017 connections.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
COORDS="${COORDS:-$HERE/../data/city_coords.txt}"
NODES="${NODES:-$HERE/../data/ar_nodes.txt}"
OUT="${1:-$HERE/../index.html}"

declare -A LAT LON
while IFS='|' read -r city lat lon; do
  [ -z "$lat" ] && continue
  LAT["$city"]="$lat"; LON["$city"]="$lon"
done < "$COORDS"

declare -A SEEN
DATA=""
missing=0; total=0
while IFS='|' read -r node call desc loc; do
  total=$((total+1))
  city=$(printf '%s' "$loc" | sed -E 's/, ?AR$//; s/^ +//; s/ +$//')
  lat="${LAT[$city]:-}"; lon="${LON[$city]:-}"
  if [ -z "$lat" ]; then missing=$((missing+1)); continue; fi
  k=${SEEN[$city]:-0}; SEEN[$city]=$((k+1))
  read jlat jlon < <(awk -v la="$lat" -v lo="$lon" -v k="$k" 'BEGIN{
    if(k==0){print la, lo} else {
      ang=k*2.399963; r=0.004*sqrt(k);
      printf "%.6f %.6f\n", la + r*cos(ang), lo + r*sin(ang)/0.82
    }}')
  call=$(printf '%s' "$call" | sed 's/\\/\\\\/g; s/"/\\"/g')
  desc=$(printf '%s' "$desc" | sed 's/\\/\\\\/g; s/"/\\"/g')
  cityj=$(printf '%s' "$city" | sed 's/\\/\\\\/g; s/"/\\"/g')
  DATA+="{n:\"$node\",c:\"$call\",d:\"$desc\",city:\"$cityj\",lat:$jlat,lon:$jlon},"$'\n'
done < "$NODES"

mapped=$((total-missing))
cat > "$OUT" <<HTML
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Arkansas AllStarLink Nodes — Live</title>
<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css"/>
<link rel="stylesheet" href="https://unpkg.com/leaflet.markercluster@1.5.3/dist/MarkerCluster.css"/>
<link rel="stylesheet" href="https://unpkg.com/leaflet.markercluster@1.5.3/dist/MarkerCluster.Default.css"/>
<style>
  html,body{margin:0;height:100%;font-family:system-ui,Segoe UI,Arial,sans-serif}
  #map{height:100%}
  .panel{position:absolute;z-index:1000;top:10px;left:50px;background:rgba(20,28,38,.93);
       color:#fff;padding:11px 14px;border-radius:8px;box-shadow:0 2px 10px rgba(0,0,0,.45);max-width:360px}
  .panel h1{font-size:16px;margin:0 0 6px}
  .panel p{font-size:12px;margin:3px 0;color:#cdd6e0}
  .stat{display:inline-block;margin-right:12px;font-size:13px;font-weight:600}
  .dot{display:inline-block;width:11px;height:11px;border-radius:50%;margin-right:4px;vertical-align:-1px}
  .on{background:#2ecc55}.off{background:#e0453a}.air{background:#ff3b1d}.act{background:#e67e22}
  .filters{margin-top:7px;font-size:12px}
  .filters label{margin-right:9px;cursor:pointer}
  #updated{color:#8fa6bd;font-size:11px}
  #actInfo{color:#ffcf99;font-size:12px;font-weight:600;min-height:14px}
  #connBtn{margin-top:8px;font-size:12px;padding:5px 9px;border:0;border-radius:6px;
           background:#f1c40f;color:#222;font-weight:700;cursor:pointer}
  #connBtn:hover{background:#f5d33a}
  .connbox{margin-top:7px;display:flex;gap:5px;align-items:center}
  .connbox input{width:92px;font-size:12px;padding:4px 6px;border:1px solid #44586c;
                 border-radius:5px;background:#0f1822;color:#fff}
  .connbox button{font-size:12px;padding:4px 9px;border:0;border-radius:5px;cursor:pointer;font-weight:600}
  #connGo{background:#3498db;color:#fff}#connGo:hover{background:#4aa9e8}
  #connClr{background:#3a4655;color:#dfe7ef}#connClr:hover{background:#4a586a}
  .disclaimer{margin-top:8px;font-size:11px;line-height:1.45;color:#ffe0a3;
              background:rgba(180,120,20,.16);border:1px solid rgba(241,196,15,.4);
              padding:6px 8px;border-radius:6px}
  .leaflet-popup-content a{color:#1565c0;text-decoration:none}
  .leaflet-popup-content a:hover{text-decoration:underline}
  #connBack{background:#5d6d7e;color:#fff}#connBack:hover:not(:disabled){background:#6e8095}
  #connBack:disabled{opacity:.4;cursor:default}
  #warnBtn{margin-top:7px;font-size:12px;padding:5px 9px;border:0;border-radius:6px;
           background:#7b241c;color:#ffd9d2;font-weight:700;cursor:pointer}
  #warnBtn:hover{background:#922b21}#warnBtn.on{background:#c0392b;color:#fff}
  #warnInfo{font-size:11px;color:#ffb3a0;margin-left:6px}
  #warnMuteLbl{font-size:11px;color:#cdd6e0;margin-left:6px;cursor:pointer}
  #warnAlert{display:none;position:absolute;top:14px;left:50%;transform:translateX(-50%);z-index:1200;
    background:linear-gradient(90deg,#c0009b,#b30000);color:#fff;font-weight:700;font-size:14px;
    padding:10px 16px;border-radius:8px;box-shadow:0 4px 18px rgba(0,0,0,.5);max-width:72%;text-align:center}
  #warnAlert.show{animation:warnpulse 1s infinite}
  #warnAlertX{cursor:pointer;margin-left:10px;font-size:18px;opacity:.85}
  @keyframes warnpulse{0%,100%{box-shadow:0 0 0 0 rgba(192,0,155,.6)}50%{box-shadow:0 0 0 12px rgba(192,0,155,0)}}
  #warnFlash{position:fixed;inset:0;pointer-events:none;z-index:1150;opacity:0}
  #warnFlash.active{animation:warnflash 1s ease-out 6}
  @keyframes warnflash{0%{opacity:0;box-shadow:inset 0 0 60px 20px rgba(224,0,0,0)}
    30%{opacity:1;box-shadow:inset 0 0 90px 34px rgba(224,0,0,.85)}
    100%{opacity:0;box-shadow:inset 0 0 60px 20px rgba(224,0,0,0)}}
  #watchInput{font-size:12px;padding:4px 6px;border:1px solid #44586c;border-radius:5px;background:#0f1822;color:#fff}
  #watchAdd{background:#3498db;color:#fff;font-size:12px;padding:4px 9px;border:0;border-radius:5px;cursor:pointer;margin-left:5px}
  #watchAdd:hover{background:#4aa9e8}
  #watchList{margin-top:4px}
  .chip{display:inline-block;background:#2c3a4a;color:#dfe7ef;font-size:11px;padding:2px 7px;border-radius:10px;margin:2px 4px 0 0}
  .chipx{cursor:pointer;color:#ff9a8a;font-weight:700;margin-left:4px}
  #connList{display:none;margin-top:7px;font-size:11.5px;line-height:1.5;max-height:210px;
            overflow:auto;background:rgba(0,0,0,.25);padding:6px 8px;border-radius:6px}
  .leaflet-popup-content{font-size:13px;line-height:1.45}
  .nn{font-weight:700;color:#1565c0}
  .badge{font-weight:700;padding:1px 6px;border-radius:4px;color:#fff;font-size:11px}
  @keyframes pulse{0%{fill-opacity:1;stroke-opacity:1}50%{fill-opacity:.25;stroke-opacity:.3}100%{fill-opacity:1;stroke-opacity:1}}
  path.pulse{animation:pulse 1s infinite}
</style>
</head>
<body>
<div class="panel">
  <h1>Arkansas AllStarLink Nodes</h1>
  <p><b>$mapped</b> registered nodes · live status from AllStarLink</p>
  <p><span class="stat"><span class="dot on"></span>Online: <span id="cOn">…</span></span>
     <span class="stat"><span class="dot off"></span>Offline: <span id="cOff">…</span></span></p>
  <div class="filters">Show:
    <label><input type="radio" name="flt" value="all" checked> All</label>
    <label><input type="radio" name="flt" value="on"> Online</label>
    <label><input type="radio" name="flt" value="off"> Offline</label>
    <label style="margin-left:6px"><input type="checkbox" id="cty" checked> Counties</label>
  </div>
  <div class="filters">
    <label><input type="checkbox" id="act"> <b>Last-keyed activity</b>
      <span class="dot air"></span>on air <span class="dot act"></span>active(10m)</label>
  </div>
  <p id="actInfo"></p>
  <button id="connBtn">Show node 65017 connections</button>
  <div class="connbox">
    <input id="connInput" type="text" inputmode="numeric" placeholder="any node #">
    <button id="connGo">Inspect</button>
    <button id="connBack" disabled>&#9664; Back</button>
    <button id="connClr">Clear</button>
  </div>
  <div id="connList"></div>
  <div class="filters">
    <button id="warnBtn">&#9888; High-impact warnings</button>
    <label id="warnMuteLbl"><input type="checkbox" id="warnMute"> mute</label>
    <span id="warnInfo"></span>
  </div>
  <div style="margin-top:6px;font-size:11px;color:#cdd6e0">Alarm area: <b>all Arkansas counties</b> + add others:</div>
  <div class="connbox" style="margin-top:4px">
    <input id="watchInput" type="text" placeholder="County, ST (e.g. Shelby, TN)" style="width:160px">
    <button id="watchAdd">Add</button>
  </div>
  <div id="watchList"></div>
  <p id="updated">loading live status…</p>
  <p style="color:#7c93aa;font-size:10.5px">Live status auto-refresh 60s ·
     Activity = key-ups observed since you opened this page (AllStarLink updates ~60s).</p>
  <div class="disclaimer">&#9888; Node positions are derived from AllStarLink <b>registry data</b> —
     registered city centroids for Arkansas nodes and operator-registered coordinates for inspected nodes —
     <b>not the actual physical repeater/antenna locations</b>. Treat all positions as approximate.</div>
</div>
<div id="map"></div>
<div id="warnFlash"></div>
<div id="warnAlert"></div>
<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
<script src="https://unpkg.com/leaflet.markercluster@1.5.3/dist/leaflet.markercluster.js"></script>
<script>
var nodes=[
$DATA
];
var API='https://stats.allstarlink.org/api/stats/';
var map=L.map('map').setView([34.85,-92.3],7);
L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
  {maxZoom:19,attribution:'&copy; OpenStreetMap contributors'}).addTo(map);

// ---- County overlay (US counties, filter Arkansas FIPS 05) ----
var countyLayer=null;
fetch('https://raw.githubusercontent.com/plotly/datasets/master/geojson-counties-fips.json')
 .then(function(r){return r.json();})
 .then(function(gj){
   var ar={type:'FeatureCollection',
     features:gj.features.filter(function(f){return String(f.id).slice(0,2)==='05';})};
   countyLayer=L.geoJSON(ar,{
     style:{color:'#3d5166',weight:1,fillColor:'#9bb4cc',fillOpacity:0.05,opacity:0.7},
     onEachFeature:function(f,l){
       l.bindTooltip(f.properties.NAME+' County',{sticky:true});
       l.on('mouseover',function(){l.setStyle({weight:2,fillOpacity:0.15});});
       l.on('mouseout',function(){l.setStyle({weight:1,fillOpacity:0.05});});
     }}).addTo(map);
   countyLayer.bringToBack();
 }).catch(function(e){console.warn('county overlay failed',e);});
document.getElementById('cty').addEventListener('change',function(e){
  if(!countyLayer)return;
  if(e.target.checked){countyLayer.addTo(map);countyLayer.bringToBack();}
  else{map.removeLayer(countyLayer);}
});

// ---- Node markers ----
var cluster=L.markerClusterGroup({maxClusterRadius:45,spiderfyOnMaxZoom:true});
var recs=nodes.map(function(o){
  var m=L.circleMarker([o.lat,o.lon],
    {radius:7,weight:1.5,color:'#1b2a38',fillColor:'#9aa7b3',fillOpacity:0.9});
  return {o:o,m:m,up:null,prevKu:null,keyedNow:false,lastKeyed:null,connHi:false};
});
var recById={}; recs.forEach(function(r){recById[String(r.o.n)]=r;});

function rel(ts){var s=Math.round((Date.now()-ts)/1000);
  if(s<60)return s+'s';var m=Math.round(s/60);if(m<60)return m+'m';return Math.round(m/60)+'h';}

function styleRec(rec){
  var up=rec.up;
  var fill=up===null?'#9aa7b3':(up?'#2ecc55':'#e0453a');
  var stroke='#1b2a38',w=1.5,r=7;
  if(activityOn){
    if(rec.keyedNow){fill='#ff3b1d';stroke='#7a0000';w=2;r=9;}
    else if(rec.lastKeyed&&Date.now()-rec.lastKeyed<600000){stroke='#e67e22';w=3;}
  }
  if(rec.connHi){stroke='#f1c40f';w=4;r=Math.max(r,8);}
  rec.m.setStyle({radius:r,weight:w,color:stroke,fillColor:fill,fillOpacity:0.9});
  var el=rec.m.getElement&&rec.m.getElement();
  if(el){ if(activityOn&&rec.keyedNow)el.classList.add('pulse');else el.classList.remove('pulse'); }
}
function popupHtml(rec){
  var up=rec.up;
  var badge=up===null?'<span class="badge" style="background:#7f8c8d">UNKNOWN</span>'
    :(up?'<span class="badge" style="background:#27ae60">ONLINE</span>'
        :'<span class="badge" style="background:#c0392b">OFFLINE</span>');
  var act='';
  if(rec.keyedNow)act='<br><b style="color:#ff3b1d">&#128308; ON AIR now</b>';
  else if(rec.lastKeyed)act='<br>Last keyed '+rel(rec.lastKeyed)+' ago <span style="color:#999">(observed)</span>';
  else if(activityOn)act='<br><span style="color:#999">no activity observed yet</span>';
  return '<span class="nn">Node '+rec.o.n+'</span> '+badge+'<br><b>'+rec.o.c+'</b><br>'+
    (rec.o.d?rec.o.d+'<br>':'')+rec.o.city+', AR'+act+
    '<br><a href="#" onclick="showConn(\''+rec.o.n+'\');return false;">&#9654; open this node&#39;s connections</a>'+
    '<br><a href="https://stats.allstarlink.org/stats/'+rec.o.n+'" target="_blank">stats &#8599;</a>';
}
recs.forEach(function(rec){
  rec.m.bindPopup(popupHtml(rec));
  rec.m.bindTooltip(rec.o.n+' · '+rec.o.c);
});

var curFilter='all';
function applyFilter(){
  cluster.clearLayers();
  var add=[];
  recs.forEach(function(rec){
    if(curFilter==='on'&&rec.up!==true)return;
    if(curFilter==='off'&&rec.up!==false)return;
    add.push(rec.m);
  });
  cluster.addLayers(add);
}
map.addLayer(cluster);
applyFilter();
map.fitBounds(L.latLngBounds(recs.map(function(r){return r.m.getLatLng();})).pad(0.08));
document.querySelectorAll('input[name=flt]').forEach(function(r){
  r.addEventListener('change',function(e){curFilter=e.target.value;applyFilter();});
});

// ---- Live online/offline status (script tag => no CORS) ----
function setStatus(onlineSet){
  var on=0,off=0;
  recs.forEach(function(rec){
    var up=onlineSet.has(String(rec.o.n));rec.up=up;up?on++:off++;
    styleRec(rec);rec.m.setPopupContent(popupHtml(rec));
  });
  document.getElementById('cOn').textContent=on;
  document.getElementById('cOff').textContent=off;
  document.getElementById('updated').textContent='Live · updated '+new Date().toLocaleTimeString();
  applyFilter();
}
function refreshStatus(){
  var s=document.createElement('script');
  s.src='https://allstarmap.org/all_online_nodes.js?_='+Date.now();
  s.onload=function(){
    try{var set=new Set((window.g_online_nodes||[]).map(function(o){return String(o.id);}));setStatus(set);}
    catch(e){console.warn('status parse failed',e);}
    s.remove();
  };
  s.onerror=function(){document.getElementById('updated').textContent='status feed unreachable — retrying…';s.remove();};
  document.body.appendChild(s);
}
refreshStatus();
setInterval(refreshStatus,60000);

// ---- Last-keyed activity (polls online nodes' stats, staggered) ----
var activityOn=false,activityTimer=null;
function fetchKey(rec){
  fetch(API+rec.o.n).then(function(r){return r.json();}).then(function(j){
    var d=j&&j.stats&&j.stats.data; if(!d)return;
    var ku=parseInt(d.totalkeyups,10);
    var keyed=(d.keyed===true||d.keyed==='true');
    if(rec.prevKu!=null&&!isNaN(ku)&&ku>rec.prevKu)rec.lastKeyed=Date.now();
    if(keyed)rec.lastKeyed=Date.now();
    if(!isNaN(ku))rec.prevKu=ku;
    rec.keyedNow=keyed;
    styleRec(rec);rec.m.setPopupContent(popupHtml(rec));
    updateActivityInfo();
  }).catch(function(){});
}
function updateActivityInfo(){
  if(!activityOn){document.getElementById('actInfo').textContent='';return;}
  var air=0,act=0,now=Date.now();
  recs.forEach(function(r){if(r.keyedNow)air++;else if(r.lastKeyed&&now-r.lastKeyed<600000)act++;});
  document.getElementById('actInfo').textContent='On air: '+air+'  ·  active last 10m: '+act;
}
function activityCycle(){
  if(!activityOn)return;
  var list=recs.filter(function(r){return r.up===true;});
  list.forEach(function(rec,i){setTimeout(function(){if(activityOn)fetchKey(rec);},i*900);});
  updateActivityInfo();
  activityTimer=setTimeout(activityCycle,Math.max(60000,list.length*900+8000));
}
document.getElementById('act').addEventListener('change',function(e){
  activityOn=e.target.checked;
  if(activityOn){document.getElementById('actInfo').textContent='polling key-up activity…';activityCycle();}
  else{
    if(activityTimer)clearTimeout(activityTimer);
    recs.forEach(function(r){r.keyedNow=false;styleRec(r);r.m.setPopupContent(popupHtml(r));});
    document.getElementById('actInfo').textContent='';
  }
});

// ---- Connection inspector (65017 button + any-node input box + back history) ----
var connNode=null,connLayer=null,connHist=[];
function validLL(la,lo){return !isNaN(la)&&!isNaN(lo)&&la>=-90&&la<=90&&lo>=-180&&lo<=180&&(Math.abs(la)>0.05||Math.abs(lo)>0.05);}
function setConnBtnLabel(){
  document.getElementById('connBtn').textContent=
    (connNode==='65017')?'Hide node 65017 connections':'Show node 65017 connections';
}
function updateBackBtn(){
  var b=document.getElementById('connBack');
  b.disabled=!connHist.length;
  b.innerHTML='&#9664; Back'+(connHist.length?' ('+connHist.length+')':'');
}
function removeConnLayer(){
  if(connLayer){map.removeLayer(connLayer);connLayer=null;}
  recs.forEach(function(r){if(r.connHi){r.connHi=false;styleRec(r);}});
  var cl=document.getElementById('connList');cl.style.display='none';cl.innerHTML='';
  connNode=null;setConnBtnLabel();
}
function clearConn(){removeConnLayer();connHist=[];updateBackBtn();}
function showConn(id,fromBack){
  id=String(id==null?'':id).trim();
  var cl=document.getElementById('connList');
  if(!/^[0-9]+$/.test(id)){cl.style.display='block';cl.innerHTML='Enter a numeric AllStar node number.';return;}
  if(!fromBack&&connNode&&connNode!==id)connHist.push(connNode);
  removeConnLayer();
  connNode=id;setConnBtnLabel();updateBackBtn();
  cl.style.display='block';cl.innerHTML='loading '+id+' connections…';
  fetch(API+id).then(function(r){return r.json();}).then(function(j){
    var d=j&&j.stats&&j.stats.data; var ln=(d&&d.linkedNodes)||[];
    connLayer=L.layerGroup().addTo(map);
    // hub position: the inspected node's own coords (centroid if on-map, else its registry coords), else central AR
    var hub=[34.72,-92.35], hubName='';
    var self=recById[id];
    if(self){var sl=self.m.getLatLng();hub=[sl.lat,sl.lng];hubName=self.o.c+' — '+self.o.city+', AR';}
    ln.forEach(function(x){if(String(x.name)===id){
      if(!hubName)hubName=((x.callsign||'')+' '+((x.server&&x.server.Location)||'')).trim();
      if(!self&&x.server){var la=parseFloat(x.server.Latitude),lo=parseFloat(x.server.Logitude);if(validLL(la,lo))hub=[la,lo];}
    }});
    var rows=[],bounds=[hub],seen={};
    ln.forEach(function(x){
      var nid=String(x.name); if(nid===id||seen[nid])return; seen[nid]=1;
      var call=((x.callsign||x.User_ID||'')+'').trim();
      var loc=(x.server&&x.server.Location)||'';
      var rec=recById[nid];
      if(rec){
        var ll=rec.m.getLatLng();
        rec.connHi=true;styleRec(rec);
        L.polyline([hub,[ll.lat,ll.lng]],{color:'#f1c40f',weight:2,opacity:.85,dashArray:'4 4'}).addTo(connLayer);
        bounds.push([ll.lat,ll.lng]);
        rows.push('<b>'+nid+'</b> '+call+' — '+loc+' <span style="color:#2ecc55">on map</span>');
      }else{
        var la=parseFloat(x.server&&x.server.Latitude),lo=parseFloat(x.server&&x.server.Logitude);
        var valid=validLL(la,lo), inAR=valid&&la>32&&la<37.6&&lo<-89&&lo>-95;
        if(valid){
          var col=inAR?'#a569bd':'#16a085', dk=inAR?'#6c3483':'#0e6655';
          var tag=inAR?'AR (not in directory)':'OUT OF STATE';
          var mk=L.circleMarker([la,lo],{radius:7,weight:2,color:dk,fillColor:col,fillOpacity:.9}).addTo(connLayer);
          mk.bindPopup('<b>Node '+nid+'</b> '+call+'<br>'+loc+'<br><i>connected to '+id+' — '+tag+'</i>'+
            '<br><a href="#" onclick="showConn(\''+nid+'\');return false;">&#9654; open this node&#39;s connections</a>');
          mk.bindTooltip(nid+' · '+call);
          L.polyline([hub,[la,lo]],{color:col,weight:2,opacity:.75,dashArray:'4 4'}).addTo(connLayer);
          bounds.push([la,lo]);
          rows.push('<b>'+nid+'</b> '+call+' — '+loc+' <span style="color:'+col+'">'+(inAR?'plotted':'out of state')+'</span>');
        }else{
          rows.push('<b>'+nid+'</b> '+call+' — '+(loc||'location n/a')+' <span style="color:#9aa7b3">no coords</span>');
        }
      }
    });
    var hubMk=L.marker(hub).addTo(connLayer);
    hubMk.bindPopup('<b>Node '+id+'</b>'+(hubName?'<br>'+hubName:'')+'<br>'+rows.length+' nodes connected').openPopup();
    if(bounds.length>1)map.fitBounds(L.latLngBounds(bounds).pad(0.25));
    cl.innerHTML='<b>'+id+' — '+rows.length+' connected</b>'+(hubName?' <span style="color:#9fb3c8">('+hubName+')</span>':'')+
      (rows.length?'<br>'+rows.join('<br>'):'<br><i>no active connections (node may be offline)</i>');
  }).catch(function(){cl.innerHTML='Failed to load connections for node '+id+'.';});
}
document.getElementById('connBtn').addEventListener('click',function(){
  if(connNode==='65017')clearConn(); else showConn('65017');
});
document.getElementById('connGo').addEventListener('click',function(){showConn(document.getElementById('connInput').value);});
document.getElementById('connInput').addEventListener('keydown',function(e){if(e.key==='Enter')showConn(this.value);});
document.getElementById('connClr').addEventListener('click',function(){clearConn();document.getElementById('connInput').value='';});
document.getElementById('connBack').addEventListener('click',function(){if(connHist.length)showConn(connHist.pop(),true);});

// ---- High-impact warning polygons (NWS): CONSIDERABLE / PDS / EMERGENCY / CATASTROPHIC ----
var warnOn=false,warnLayer=null,warnTimer=null,warnSeen={},warnMuted=false,warnAudio=null,watchExtra=[];
var WX_AREA='AR,MO,OK,TX,LA,MS,TN';   // Arkansas + bordering states
// Watch list: ALL Arkansas counties by default (SAME 005xxx / ", AR"), plus user-added out-of-state counties.
function normCounty(s){return s.toUpperCase().replace(/\b(COUNTY|PARISH)\b/g,'').replace(/\s+/g,' ').replace(/\s*,\s*/g,', ').trim();}
function inWatch(pr){
  var same=(pr.geocode&&pr.geocode.SAME)||[];
  for(var i=0;i<same.length;i++){if(/^005/.test(same[i]))return true;}   // any Arkansas county
  var area=(pr.areaDesc||'').toUpperCase();
  if(/,\s*AR\b/.test(area))return true;
  for(var j=0;j<watchExtra.length;j++){if(area.indexOf(watchExtra[j])>=0)return true;}
  return false;
}
function renderWatchChips(){
  var el=document.getElementById('watchList');
  el.innerHTML=watchExtra.map(function(c,i){return '<span class="chip">'+c+'<span class="chipx" data-i="'+i+'">&times;</span></span>';}).join('');
  [].forEach.call(el.querySelectorAll('.chipx'),function(x){x.onclick=function(){watchExtra.splice(+x.getAttribute('data-i'),1);renderWatchChips();};});
}
document.getElementById('watchAdd').addEventListener('click',function(){
  var v=document.getElementById('watchInput').value.trim();
  if(!v)return;
  var n=normCounty(v);
  if(n&&watchExtra.indexOf(n)<0)watchExtra.push(n);
  document.getElementById('watchInput').value='';renderWatchChips();
});
document.getElementById('watchInput').addEventListener('keydown',function(e){if(e.key==='Enter')document.getElementById('watchAdd').click();});
function classifyWarn(p){
  var par=p.parameters||{};
  function v(k){return ((par[k]||[]).join(',')||'').toUpperCase();}
  var td=v('tornadoDamageThreat'),st=v('thunderstormDamageThreat'),fd=v('flashFloodDamageThreat');
  var txt=((p.description||'')+' '+(p.headline||'')+' '+((par.NWSheadline||[]).join(' '))).toUpperCase();
  var tags=[];
  if(td.indexOf('CATASTROPHIC')>=0||fd.indexOf('CATASTROPHIC')>=0)tags.push('CATASTROPHIC');
  if(txt.indexOf('TORNADO EMERGENCY')>=0||txt.indexOf('FLASH FLOOD EMERGENCY')>=0)tags.push('EMERGENCY');
  if(st.indexOf('DESTRUCTIVE')>=0)tags.push('DESTRUCTIVE');
  if(txt.indexOf('PARTICULARLY DANGEROUS SITUATION')>=0)tags.push('PDS');
  if(td.indexOf('CONSIDERABLE')>=0||st.indexOf('CONSIDERABLE')>=0||fd.indexOf('CONSIDERABLE')>=0)tags.push('CONSIDERABLE');
  return tags;
}
function warnColor(tags){
  if(tags.indexOf('CATASTROPHIC')>=0||tags.indexOf('EMERGENCY')>=0)return '#c0009b';
  if(tags.indexOf('DESTRUCTIVE')>=0)return '#b30000';
  if(tags.indexOf('PDS')>=0)return '#e8491d';
  return '#f39c12';
}
var WARN_TITLE='Arkansas AllStarLink Nodes — Live';
function warnBeep(){
  if(warnMuted||!warnAudio)return;
  try{
    var ctx=warnAudio,t=ctx.currentTime;
    [880,660,880,660,990].forEach(function(f,i){
      var o=ctx.createOscillator(),g=ctx.createGain();
      o.type='square';o.frequency.value=f;o.connect(g);g.connect(ctx.destination);
      var s=t+i*0.3;
      g.gain.setValueAtTime(0.0001,s);
      g.gain.exponentialRampToValueAtTime(0.3,s+0.02);
      g.gain.exponentialRampToValueAtTime(0.0001,s+0.27);
      o.start(s);o.stop(s+0.28);
    });
  }catch(e){}
}
function flashTitle(msg){
  clearInterval(window.__warnTitle);var n=0;
  window.__warnTitle=setInterval(function(){document.title=(n%2)?msg:WARN_TITLE;if(++n>24){clearInterval(window.__warnTitle);document.title=WARN_TITLE;}},700);
}
function triggerWarnAlert(news){
  warnBeep();
  var first=news[0];
  var msg=news.length+' NEW high-impact warning'+(news.length>1?'s':'')+': '+first.event+' — '+
          first.tags.join(' · ')+' ('+first.area+')'+(news.length>1?'  +'+(news.length-1)+' more':'');
  var b=document.getElementById('warnAlert');
  b.innerHTML='&#9888; '+msg+' <span id="warnAlertX">&times;</span>';
  b.style.display='block';b.className='show';
  document.getElementById('warnAlertX').onclick=function(){b.style.display='none';clearInterval(window.__warnTitle);document.title=WARN_TITLE;};
  var fl=document.getElementById('warnFlash');fl.classList.remove('active');void fl.offsetWidth;fl.classList.add('active');
  flashTitle('⚠ NEW WARNING');
  try{if(window.Notification&&Notification.permission==='granted')new Notification('High-impact weather warning',{body:msg});}catch(e){}
  clearTimeout(window.__warnHide);window.__warnHide=setTimeout(function(){b.style.display='none';},20000);
}
function renderWarnings(feats){
  if(warnLayer){map.removeLayer(warnLayer);}
  warnLayer=L.featureGroup().addTo(map);
  var shown=0,wc=0,byTier={},news=[];
  (feats||[]).forEach(function(f){
    if(!f.geometry)return;
    var pr=f.properties||{};
    var tags=classifyWarn(pr); if(!tags.length)return;
    var col=warnColor(tags); shown++;
    var watched=inWatch(pr); if(watched)wc++;
    tags.forEach(function(t){byTier[t]=(byTier[t]||0)+1;});
    var id=f.id||pr.id||((pr.event||'')+'|'+(pr.areaDesc||''));
    if(!warnSeen[id]){warnSeen[id]=1;news.push({id:id,event:pr.event||'Warning',tags:tags,area:(pr.areaDesc||'').split(';')[0],watched:watched});}
    var exp=pr.expires?new Date(pr.expires).toLocaleString():'';
    var st=watched?{color:col,weight:2,fillColor:col,fillOpacity:0.25}
                  :{color:col,weight:1,fillColor:col,fillOpacity:0.08,dashArray:'5 5'};
    L.geoJSON(f.geometry,{style:st})
      .bindPopup('<b>'+(pr.event||'Warning')+'</b><br><b style="color:'+col+'">'+tags.join(' &middot; ')+
        '</b><br>'+(pr.areaDesc||'')+'<br><span style="color:#777">expires '+exp+'</span>'+
        (watched?'':'<br><i style="color:#999">outside watch list — no alarm</i>'))
      .addTo(warnLayer);
  });
  var info=document.getElementById('warnInfo');
  if(shown){
    var parts=Object.keys(byTier).map(function(k){return k.toLowerCase()+':'+byTier[k];});
    info.innerHTML='<b>'+shown+'</b> active, <b>'+wc+'</b> in watch ('+parts.join(', ')+') &middot; '+new Date().toLocaleTimeString();
    try{map.fitBounds(warnLayer.getBounds().pad(0.2));}catch(e){}
  }else{info.textContent='none active (AR + neighbors) · '+new Date().toLocaleTimeString();}
  var newsW=news.filter(function(w){return w.watched;});
  if(newsW.length&&warnOn)triggerWarnAlert(newsW);
  return shown;
}
function loadWarnings(){
  fetch('https://api.weather.gov/alerts/active?area='+WX_AREA,{headers:{'Accept':'application/geo+json'}})
   .then(function(r){return r.json();})
   .then(function(j){renderWarnings(j.features);})
   .catch(function(e){document.getElementById('warnInfo').textContent='weather feed error';});
}
document.getElementById('warnMute').addEventListener('change',function(e){warnMuted=e.target.checked;});
document.getElementById('warnBtn').addEventListener('click',function(){
  warnOn=!warnOn; this.classList.toggle('on',warnOn);
  if(warnOn){
    try{warnAudio=warnAudio||new (window.AudioContext||window.webkitAudioContext)();if(warnAudio.state==='suspended')warnAudio.resume();}catch(e){}
    try{if(window.Notification&&Notification.permission==='default')Notification.requestPermission();}catch(e){}
    document.getElementById('warnInfo').textContent='loading NWS alerts…';loadWarnings();warnTimer=setInterval(loadWarnings,90000);
  }else{
    if(warnTimer)clearInterval(warnTimer);
    if(warnLayer){map.removeLayer(warnLayer);warnLayer=null;}
    document.getElementById('warnInfo').textContent='';
    var b=document.getElementById('warnAlert');if(b)b.style.display='none';
    clearInterval(window.__warnTitle);document.title=WARN_TITLE;
  }
});
</script>
</body>
</html>
HTML
echo "Wrote $OUT  ($mapped mapped / $total total, $missing missing)"
