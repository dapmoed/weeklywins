const W=1920,H=1080,cv=document.querySelector('#c'),ctx=cv.getContext('2d');
const C={paper:'#F4EAD5',paperD:'#E6D8BC',ink:'#302924',blue:'#7D93AB',blueD:'#586E87',blueL:'#A9BBD0',cream:'#FBF5E8',mustard:'#E7B84B',coral:'#D96C52',teal:'#64AAA3',plum:'#74586D',olive:'#A6A765',pink:'#E5A99C'};
const clamp=(v,a=0,b=1)=>Math.max(a,Math.min(b,v)),ease=v=>{v=clamp(v);return v*v*(3-2*v)},beat=t=>Math.floor(t*12)/12;
function shape(points,fill,stroke=C.ink,lw=6,seed=0){ctx.beginPath();points.forEach(([x,y],i)=>i?ctx.lineTo(x,y):ctx.moveTo(x,y));ctx.closePath();ctx.save();ctx.translate(5+(seed%3),4);ctx.fillStyle=fill;ctx.fill();ctx.restore();ctx.beginPath();points.forEach(([x,y],i)=>i?ctx.lineTo(x,y):ctx.moveTo(x,y));ctx.closePath();ctx.lineWidth=lw;ctx.strokeStyle=stroke;ctx.lineJoin='round';ctx.stroke();}
function ellipse(x,y,rx,ry,fill,stroke=C.ink,lw=6){const p=[];for(let i=0;i<64;i++){const a=i*Math.PI/32;p.push([x+rx*Math.cos(a),y+ry*Math.sin(a)])}shape(p,fill,stroke,lw,(x+y)|0)}
function rr(x,y,w,h,r,fill,stroke=C.ink,lw=5){ctx.beginPath();ctx.roundRect(x+5,y+4,w,h,r);ctx.fillStyle=fill;ctx.fill();ctx.beginPath();ctx.roundRect(x,y,w,h,r);ctx.strokeStyle=stroke;ctx.lineWidth=lw;ctx.stroke()}
function line(points,color=C.ink,lw=6){ctx.beginPath();points.forEach(([x,y],i)=>i?ctx.lineTo(x,y):ctx.moveTo(x,y));ctx.strokeStyle=color;ctx.lineWidth=lw;ctx.lineCap='round';ctx.lineJoin='round';ctx.stroke()}
function text(str,x,y,size=54,align='center',color=C.ink,font='Arial'){ctx.textAlign=align;ctx.textBaseline='middle';ctx.font=`700 ${size}px ${font}`;ctx.fillStyle='rgba(216,108,82,.5)';ctx.fillText(str,x+4,y+4);ctx.fillStyle=color;ctx.fillText(str,x,y)}
function rays(x,y,r,n=20,color='rgba(247,211,127,.62)'){ctx.save();ctx.translate(x,y);for(let i=0;i<n;i++){ctx.rotate(Math.PI*2/n);ctx.beginPath();ctx.moveTo(0,-r*.67);ctx.lineTo(0,-r);ctx.strokeStyle=color;ctx.lineWidth=6;ctx.stroke()}ctx.restore()}
function bg(ground,floor){ctx.fillStyle=ground;ctx.fillRect(0,0,W,H);ctx.fillStyle=floor;ctx.fillRect(0,805,W,275);line([[0,807],[330,807],[366,804],[738,807],[1105,806],[1460,807],[1920,805]],'rgba(48,41,36,.45)',5);}
function kitty(x,y,s=1,pose='sit',t=0){ctx.save();ctx.translate(x,y);ctx.scale(s,s);const p=beat(t),bob=Math.sin(p*7)*3;
  // tail always keeps the blue-grey coat; a curled comma silhouette
  line([[158,64+bob],[230,76+bob],[278,49+bob],[282,15+bob],[256,-5+bob],[230,8+bob]],C.ink,28);line([[158,64+bob],[230,76+bob],[278,49+bob],[282,15+bob],[256,-5+bob],[230,8+bob]],C.blue,19);
  if(pose==='loaf'){
    ellipse(0,48+bob,154,112,C.blue,C.ink,7);ellipse(4,60+bob,85,66,C.blueL,'rgba(48,41,36,.25)',3);
    // paws tucked under the round body
    ellipse(-70,123+bob,47,21,C.blueD,C.ink,4);ellipse(57,123+bob,49,21,C.blueD,C.ink,4);
  } else {
    ellipse(0,112+bob,105,116,C.blue,C.ink,7);ellipse(0,144+bob,58,70,C.blueL,'rgba(48,41,36,.24)',3);
    ellipse(-56,211+bob,42,23,C.blueD,C.ink,4);ellipse(55,211+bob,42,23,C.blueD,C.ink,4);
  }
  // round British shorthair cheeks, with small ears tucked into the silhouette
  shape([[-83,-111],[-90,-154],[-53,-139],[-25,-158],[25,-158],[53,-139],[90,-154],[82,-109]],C.blue,C.ink,6,23);
  ellipse(0,-82,99,78,C.blue,C.ink,7);ellipse(-47,-82,22,29,C.blueL,C.ink,3);ellipse(47,-82,22,29,C.blueL,C.ink,3);
  // round amber eyes; closed lids on the sleeping pose
  if(pose==='sleep'||pose==='loaf'){line([[-56,-86],[-43,-79],[-30,-86]],C.ink,5);line([[28,-86],[41,-79],[54,-86]],C.ink,5)}
  else {ellipse(-40,-87,14,19,'#D5A74D',C.ink,3);ellipse(40,-87,14,19,'#D5A74D',C.ink,3);ellipse(-38,-87,5,12,C.ink,C.ink,1);ellipse(42,-87,5,12,C.ink,C.ink,1);ellipse(-42,-93,4,5,C.cream,'none',0);ellipse(38,-93,4,5,C.cream,'none',0)}
  // muzzle and tiny nose
  ellipse(-16,-44,25,18,C.blueL,'rgba(48,41,36,.28)',2);ellipse(16,-44,25,18,C.blueL,'rgba(48,41,36,.28)',2);shape([[-8,-49],[8,-49],[1,-40]],C.coral,C.ink,2,1);line([[1,-40],[1,-30],[-10,-25]],C.ink,3);line([[2,-30],[13,-25]],C.ink,3);
  for(let j=0;j<3;j++){line([[-36,-43-j*5],[-87,-51-j*8]],'rgba(48,41,36,.55)',2);line([[36,-43-j*5],[87,-51-j*8]],'rgba(48,41,36,.55)',2)}
  if(pose==='eat'){
    ellipse(0,246,83,27,C.mustard,C.ink,5);ellipse(0,238,68,17,C.cream,C.ink,3);for(let i=0;i<5;i++)ellipse(-42+i*21,236+(i%2)*4,6,4,'#B47C4B','none',0);
    const lick=ease((Math.sin(t*11)+1)/2);ellipse(0,-25+lick*8,8,13,C.coral,C.coral,1);
  }
  if(pose==='sleep'){
    // eyelids, breathing belly, floating z marks
    line([[-56,-87],[-43,-80],[-30,-87]],C.ink,5);line([[28,-87],[41,-80],[54,-87]],C.ink,5);text('z',116,-170,43,'center',C.plum,'Georgia');text('z',155,-218,30,'center',C.plum,'Georgia');
  }
  if(pose==='walk'){line([[ -48,192],[-62,232],[-75,240]],C.ink,9);line([[44,190],[61,220],[72,226]],C.ink,9);}
  ctx.restore();
}
function med(n,title){ellipse(178,178,58,58,C.coral,C.ink,5);text(String(n),178,179,58,'center',C.cream,'Georgia');rr(270,137,455,82,18,C.cream,C.ink,4);text(title,497,179,38,'center',C.ink,'Arial')}
function bowl(x,y){ellipse(x,y,118,24,C.coral,C.ink,5);ctx.beginPath();ctx.ellipse(x,y-5,96,15,0,0,Math.PI);ctx.fillStyle=C.cream;ctx.fill();line([[x-103,y],[x-91,y+47],[x+90,y+47],[x+104,y]],C.ink,5);line([[x-91,y+47],[x+90,y+47]],C.ink,5)}
function caption(str){rr(325,939,1270,82,14,C.paper,C.ink,3);text(str,960,981,35,'center',C.ink,'Arial')}
function drawScene(t){const c=ctx;
 if(t<4){bg('#E7B84B','#CE9C48');rays(960,375,300,24);text('МИСТЕР ПЛЮШ',960,116,58,'center',C.ink,'Georgia');text('Инструкция по идеальному дню',960,187,39,'center',C.ink);kitty(960,542,1.18,'eat',t);caption('У кота всего три важных дела.');}
 else if(t<12){bg('#D98F82','#BE7B6C');med(1,'ПЕРВОЕ ДЕЛО — ЕДА');kitty(956,526,1.18,'eat',t);if(t>8){text('ЕЩЁ?',1226,434,42,'center',C.ink,'Georgia');}caption('Первый: съесть всё. Проверить миску. На всякий случай.');}
 else if(t<20){bg('#A6A765','#82894E');med(2,'ВОССТАНОВИТЬ СИЛЫ');rr(690,630,540,186,75,'#DDBF86',C.ink,5);kitty(962,565,1.2,'loaf',t);text('Z',1223,395,55,'center',C.plum,'Georgia');caption('Второй: восстановить силы. Немедленно.');}
 else if(t<30){bg('#7F9CC0','#637C9C');med(3,'ЛОТОК. ПО ПЛАНУ.');
   // clean litter tray remains visible beside a screen; the mishap is implied offstage
   rr(1221,634,387,174,42,C.cream,C.ink,5);rr(1247,678,337,113,30,'#D3BE98',C.ink,3);for(let i=0;i<12;i++)ellipse(1280+(i%4)*82,705+Math.floor(i/4)*25,5,4,'#B99C71','none',0);
   kitty(802+ease((t-20)/5)*132,530,1.05,'walk',t);
   if(t<27.4){rr(1182,440,556,447,36,C.coral,C.ink,6);for(let i=0;i<4;i++)line([[1190+i*144,470],[1190+i*144,845]],'#B74F42',3);text('ТИШИНА…',1460,519,40,'center',C.cream,'Georgia');}
   else {ellipse(1012,740,37,19,C.blue,C.ink,3);text('✓',1455,557,63,'center','#64895D','Georgia');}
   caption('Третий: воспользоваться лотком. По крайней мере, таков был план.');
 }
 else {bg('#74586D','#594354');rays(960,395,335,24,'rgba(231,184,75,.5)');text('ИТОГО: ВСЁ ИДЁТ ПО ПЛАНУ',960,135,44,'center',C.cream,'Georgia');bowl(1217,743);kitty(891,522,1.13,'sit',t);text('ПОЧТИ.',960,882,48,'center',C.mustard,'Georgia');caption('Идеально. Почти.');}
}
function circleReveal(t,center,duration){const r=ease((t-center)/duration)*1500;ctx.save();ctx.beginPath();ctx.arc(960,540,r,0,Math.PI*2);ctx.clip();ctx.fillStyle=C.paper;ctx.fillRect(0,0,W,H);drawScene(t);ctx.restore()}
window.DUR=35;window.EV=[];window.READY=true;
window.TEXTS=t=>{
  const all=[];const add=(id,text,x0,y0,x1,y1)=>all.push({id,text,x0,y0,x1,y1});
  if(t<4){add('title','МИСТЕР ПЛЮШ',570,70,1350,160);add('subtitle','Инструкция по идеальному дню',510,150,1410,225);add('caption','У кота всего три важных дела.',320,930,1600,1030)}
  else if(t<12){add('step1','ПЕРВОЕ ДЕЛО — ЕДА',250,125,750,225);add('caption','Первый: съесть всё. Проверить миску. На всякий случай.',320,930,1600,1030);if(t>8)add('aside','ЕЩЁ?',1160,405,1320,470)}
  else if(t<20){add('step2','ВОССТАНОВИТЬ СИЛЫ',250,125,750,225);add('caption','Второй: восстановить силы. Немедленно.',320,930,1600,1030);add('zzz','Z',1190,360,1260,430)}
  else if(t<30){add('step3','ЛОТОК. ПО ПЛАНУ.',250,125,750,225);add('caption','Третий: воспользоваться лотком. По крайней мере, таков был план.',320,930,1600,1030);if(t<27.4)add('curtain','ТИШИНА…',1180,485,1740,560)}
  else {add('outro','ИТОГО: ВСЁ ИДЁТ ПО ПЛАНУ',560,90,1370,175);add('almost','ПОЧТИ.',820,850,1110,915);add('caption','Идеально. Почти.',320,930,1600,1030)}
  return all;
};
window.render=t=>{
  ctx.setTransform(1,0,0,1,0,0);ctx.clearRect(0,0,W,H);const tt=beat(t);drawScene(tt);
  // A 1950s colour-block page turn at each step change.
  const cuts=[[4,'#E7B84B'],[12,'#D98F82'],[20,'#A6A765'],[30,'#7F9CC0']];
  for(const [at,col] of cuts){const u=clamp((t-at)/.42);if(u>0&&u<1){ctx.fillStyle=col;ctx.fillRect(0,H*(1-ease(u)),W,H*ease(u));}}
};
