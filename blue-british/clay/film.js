import * as T from '/node_modules/three/build/three.module.js';

const renderer = new T.WebGLRenderer({canvas: document.querySelector('#picture'), antialias:true, preserveDrawingBuffer:true});
renderer.setSize(1920,1080,false);
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = T.PCFShadowMap;
renderer.toneMapping = T.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.14;
const camera = new T.PerspectiveCamera(34,16/9,.1,50);
const scene = new T.Scene();
const canvas = document.querySelector('#titles');
const titles = canvas.getContext('2d');
const clamp = t => Math.min(1,Math.max(0,t));
const smooth = t => { const v=clamp(t); return v*v*(3-2*v); };

const clayTexture = document.createElement('canvas');
clayTexture.width = clayTexture.height = 256;
const grain = clayTexture.getContext('2d');
const pixels = grain.createImageData(256,256);
let seed = 2189;
function random() {
  seed = (Math.imul(seed,1664525)+1013904223) >>> 0;
  return seed / 4294967296;
}
for(let y=0;y<256;y++) for(let x=0;x<256;x++){
  const i=(y*256+x)*4;
  const value=128+27*Math.sin(x*.13+Math.sin(y*.073)*2)+12*Math.sin(y*.23+x*.04)+26*(random()-.5);
  pixels.data.set([value,value,value,255],i);
}
grain.putImageData(pixels,0,0);
const bump = new T.CanvasTexture(clayTexture);
function clay(color, roughness=.82, bumpScale=.042) {
  return new T.MeshStandardMaterial({color,roughness,bumpMap:bump,bumpScale});
}
const coat=clay(0x7089a9), cheek=clay(0x8fa6bd), dark=clay(0x526983);
const innerEar=clay(0x9b8192), nose=clay(0x805364), ink=clay(0x3c3442);
const amber=clay(0xdb922e,.34,.008), irisLight=clay(0xffbd56,.37,.006);
const pupil=clay(0x241d23,.24,.003), white=clay(0xfff1d5,.32,.005);
const whisker=clay(0xd6d3ca);
const sphere = new T.SphereGeometry(1,48,32);

function place(parent, mesh, x,y,z) {
  parent.add(mesh);
  mesh.position.set(x,y,z);
  mesh.castShadow=true;
  mesh.receiveShadow=true;
  return mesh;
}
function oval(parent,mat,x,y,z,sx,sy,sz,rotation=0) {
  const mesh=place(parent,new T.Mesh(sphere,mat),x,y,z);
  mesh.scale.set(sx,sy,sz);
  mesh.rotation.z=rotation;
  return mesh;
}
function box(parent,mat,x,y,z,w,h,d) {
  return place(parent,new T.Mesh(new T.BoxGeometry(w,h,d),mat),x,y,z);
}
function strand(parent,material,coords,radius) {
  const path=new T.CatmullRomCurve3(coords.map(p=>new T.Vector3(...p)));
  return place(parent,new T.Mesh(new T.TubeGeometry(path,28,radius,8,false),material),0,0,0);
}
function group(parent,x=0,y=0,z=0) {
  const g=new T.Group();
  g.position.set(x,y,z);
  parent.add(g);
  return g;
}

scene.add(new T.HemisphereLight(0xffe6cf,0x787095,2.15));
const key = new T.DirectionalLight(0xffe1be,3.2);
key.position.set(-3.5,6.5,4);
key.castShadow=true;
key.shadow.mapSize.set(1536,1536);
key.target.position.x=2;
scene.add(key.target);
Object.assign(key.shadow.camera,{left:-9,right:9,top:7,bottom:-7,near:.3,far:24});
key.shadow.normalBias=.025;
key.shadow.radius=3;
key.shadow.bias=-.00016;
scene.add(key);
const edge = new T.DirectionalLight(0xc2d8ff,1.7);
edge.position.set(4,4,-3);
scene.add(edge);

const plaster=clay(0xc78b72), bathWall=clay(0xa0ad9f);
const timber=clay(0x80553f), ivory=clay(0xe1be9a), grout=clay(0x526e6c);
const tile=[clay(0x8ea6a0),clay(0x9aafab),clay(0x839d9d)];
const planks=[clay(0xaf7551),clay(0xb9815a),clay(0xc18b64)];
scene.background=new T.Color(0x574650);
box(scene,timber,0,-.18,0,32,.32,24);
box(scene,plaster,-3,2.2,-2.9,12,4.4,.22);
box(scene,bathWall,5.9,2.4,-2.9,6,4.8,.22);
box(scene,bathWall,8.83,2.4,-.03,.21,4.8,5.84);
box(scene,ivory,-3,.14,-2.74,12,.24,.12);
for(let row=0;row<21;row++){
  for(let col=0;col<4;col++){
    const stagger=(row%2)*.29;
    box(scene,planks[(row+col*2)%3],-7.6+col*3+stagger,-.027,-2.66+row*.43,2.985,.05,.416);
  }
}
box(scene,grout,5.9,-.028,0,6,.052,7.8);
for(let row=0;row<11;row++) for(let col=0;col<8;col++){
  box(scene,tile[(row*2+col)%3],3.28+col*.73,-.012,-2.46+row*.73,.706,.03,.706);
}
for(let row=0;row<3;row++) for(let col=0;col<10;col++){
  box(scene,tile[(row+col)%3],3.2+col*.58,.29+row*.55,-2.745,.554,.523,.08);
}
box(scene,ivory,5.9,1.68,-2.69,6,.10,.12);

// The opening in the shared wall lines up with the cat's path.
const doorwayX=2.9;
box(scene,plaster,doorwayX,2.2,-1.96,.26,4.4,1.7);
box(scene,plaster,doorwayX,3.95,.03,.26,.9,2.3);
for(const z of [-1.05,1.06]) box(scene,timber,doorwayX,1.75,z,.34,3.5,.17);
box(scene,timber,doorwayX,3.47,0,.34,.18,2.28);
box(scene,ivory,doorwayX,.018,0,.35,.06,2.04);
const openDoor=box(scene,clay(0xb47752),doorwayX+.97,1.68,-1.16,1.98,3.33,.12);
openDoor.rotation.y=.14;
oval(scene,timber,doorwayX+1.76,1.59,-.93,.075,.075,.06);

const runner=clay(0x6c7c7c,.96,.09);
box(scene,runner,-2.16,.018,.2,7.9,.045,1.76);
for(const z of [-.56,.96]) box(scene,ivory,-2.16,.044,z,7.85,.012,.05);
for(let i=0;i<13;i++) box(scene,ivory,-6.18,.036,-.59+i*.13,.17,.014,.036);

const consoleWood=clay(0x7e4e3e);
box(scene,consoleWood,-3.8,.98,-2.1,2.55,.18,1.04);
box(scene,consoleWood,-3.8,.23,-2.1,2.44,.13,.91);
for(const x of [-4.92,-2.68]) for(const z of [-2.46,-1.72]){
  box(scene,consoleWood,x,.55,z,.14,1.04,.13);
}
for(const x of [-4.62,-4.2]){
  oval(scene,clay(0x554c58),x,.4,-1.99,.18,.14,.31);
}
const pot=clay(0xdc9867), leaf=clay(0x617953);
oval(scene,pot,-3,1.27,-2.13,.28,.27,.27);
for(let i=0;i<6;i++){
  oval(scene,leaf,-3+(i-2.5)*.116,1.67+(i%2)*.14,-2.13,.125,.37,.08,(2.5-i)*.22);
}
box(scene,timber,-1.2,2.68,-2.67,1.45,1.04,.12);
box(scene,ivory,-1.2,2.68,-2.59,1.28,.86,.06);
oval(scene,clay(0xbb6d52),-1.34,2.76,-2.54,.27,.27,.018);
oval(scene,runner,-.97,2.5,-2.54,.29,.14,.018,.35);

const porcelain=clay(0xf2e6d2,.49,.014);
const water=clay(0x809fa4,.32,.015);
const toiletX=7.1;
oval(scene,porcelain,toiletX,.26,-1.96,.37,.30,.39);
oval(scene,porcelain,toiletX,.62,-1.79,.55,.31,.67);
oval(scene,porcelain,toiletX,.87,-1.74,.56,.114,.62);
oval(scene,water,toiletX,.952,-1.71,.39,.034,.45);
box(scene,porcelain,toiletX,1.31,-2.43,1.02,.82,.47);
box(scene,porcelain,toiletX,1.75,-2.43,1.11,.12,.55);
oval(scene,ivory,toiletX,1.824,-2.42,.105,.028,.068);
const towel=clay(0x9695b1,.96,.08);
box(scene,timber,5.78,2.18,-2.55,1.05,.07,.09);
box(scene,towel,5.78,1.91,-2.49,.63,.55,.08);
for(const y of [1.69,1.77]) box(scene,ivory,5.78,y,-2.442,.62,.028,.018);
oval(scene,porcelain,8.04,1.02,-2.32,.11,.19,.11);

const toy=group(scene);
const wool=clay(0xb35047,.95,.11), thread=clay(0xe18b6c,.95,.09);
oval(toy,wool,0,0,0,.253,.247,.25);
for(let band=0;band<6;band++){
  const curve=[];
  for(let i=0;i<=24;i++){
    const angle=i*Math.PI/12;
    const wave=.255*Math.sin(angle*2+band*.63);
    curve.push([.247*Math.cos(angle),wave*.21,.247*Math.sin(angle)]);
  }
  const wrap=strand(toy,thread,curve,.009);
  wrap.rotation.x=band*.52;
  wrap.rotation.z=band*.22;
}

const cat=group(scene);
const torso=oval(cat,coat,0,1.02,-.09,1.06,1.04,.89);
oval(cat,dark,-.7,.56,-.12,.49,.46,.64,.23);
oval(cat,coat,.7,.55,-.12,.5,.48,.66,-.22);
const chest=oval(cat,cheek,-.05,1.07,.46,.69,.79,.47,-.09);
const paws=[];
for(const side of [-1,1]){
  const paw=group(cat,side*.46,.33,.62);
  oval(paw,coat,0,.16,-.05,.29,.41,.3,side*.09);
  oval(paw,coat,0,-.11,.16,.33,.2,.37);
  for(const toe of [-1,1]){
    strand(paw,dark,[[toe*.085,.018,.446],[toe*.098,-.024,.487],[toe*.104,-.082,.518]],.009);
  }
  paws.push(paw);
}
const tail=group(cat,.63,.48,-.5);
strand(tail,coat,[[0,0,0],[.50,-.05,-.12],[1,-.06,.02],[1.3,.04,.34],[1.29,.25,.52],[1.1,.42,.55]],.157);
oval(tail,coat,1.1,.42,.55,.16,.16,.16);

const head=group(cat,0,2.01,.31);
const headGeometry=sphere.clone();
const vertices=headGeometry.getAttribute('position');
for(let i=0;i<vertices.count;i++){
  const y=vertices.getY(i);
  const fullness=Math.exp(-Math.pow((y+.36)/.36,2));
  vertices.setXYZ(i,vertices.getX(i)*(1+.16*fullness),y,vertices.getZ(i)*(1+.13*fullness));
}
headGeometry.computeVertexNormals();
const skull=place(head,new T.Mesh(headGeometry,coat),0,.01,0);
skull.scale.set(1.04,.85,.77);
for(const side of [-1,1]){
  oval(head,coat,side*.67,.66,-.03,.265,.34,.22,side*.35);
  oval(head,innerEar,side*.69,.69,.132,.148,.22,.083,side*.35);
}
const eyes=group(head);
const lids=group(head);
for(const side of [-1,1]){
  const x=side*.385;
  oval(eyes,dark,x,.09,.648,.265,.277,.192,side*.08);
  oval(eyes,amber,x,.084,.763,.205,.225,.11,side*.08);
  oval(eyes,irisLight,x-.018,.025,.848,.135,.133,.032);
  oval(eyes,pupil,x+.025,.088,.857,.107,.162,.055);
  oval(eyes,white,x-.015,.17,.905,.041,.047,.019);
  oval(eyes,white,x+.067,.028,.901,.018,.019,.011);
  strand(lids,ink,[[x-.16,.063,.794],[x-.08,.018,.841],[x,.006,.854],[x+.09,.023,.84],[x+.16,.067,.794]],.022);
}
const muzzle=group(head,0,-.28,.66);
for(const side of [-1,1]){
  oval(muzzle,cheek,side*.18,-.015,.088,.263,.207,.20,side*.13);
  for(let i=0;i<3;i++){
    oval(muzzle,dark,side*(.22+i*.05),.01-(i%2)*.064,.265-i*.013,.016,.016,.009);
    strand(muzzle,whisker,[[side*.29,-.04+i*.039,.242],[side*.53,-.03+i*.087,.251],[side*(.82+i*.025),-.09+i*.15,.17]],.009);
  }
}
oval(muzzle,nose,0,.115,.251,.118,.073,.096);
oval(muzzle,nose,0,.071,.276,.065,.063,.056);
oval(muzzle,cheek,-.031,.153,.325,.038,.012,.016);
strand(muzzle,ink,[[0,.06,.309],[0,-.035,.284],[-.09,-.091,.26],[-.156,-.066,.245]],.012);
strand(muzzle,ink,[[0,-.035,.284],[.09,-.091,.26],[.156,-.066,.245]],.012);
const tongue=oval(muzzle,clay(0xc87986),0,-.155,.26,.077,.1,.04);

const bowl=group(scene);
const ceramic=clay(0xbd6244,.55), rim=clay(0xf0ab6e,.47), inside=clay(0xa84735,.66);
const bowlContour=[[0,0],[.39,0],[.52,.1],[.64,.28],[.65,.32],[.61,.34],[.57,.31],[.49,.17],[.38,.105],[0,.10]].map(([x,y])=>new T.Vector2(x,y));
place(bowl,new T.Mesh(new T.LatheGeometry(bowlContour,64),ceramic),0,.02,0);
const bowlLip=place(bowl,new T.Mesh(new T.TorusGeometry(.623,.028,14,64),rim),0,.353,0);
bowlLip.rotation.x=Math.PI/2;
oval(bowl,inside,0,.124,0,.39,.021,.39);
const treats=[];
const biscuit=clay(0x9c5838);
for(let i=0;i<9;i++){
  const radius=.19+random()*.2;
  treats.push(oval(bowl,biscuit,Math.cos(i*2.4)*radius,.15+random()*.06,Math.sin(i*2.4)*radius,.069,.055,.056,i));
}

const cushion=group(scene,-.68,.15,.13);
const fabric=clay(0xc68549,.95,.1);
oval(cushion,fabric,0,0,0,1.82,.29,1.14);
const seam=clay(0xe6a968,.92);
for(let i=0;i<52;i++){
  const a=i*(Math.PI*2/52);
  const stitch=oval(cushion,seam,Math.cos(a)*1.71,.095,Math.sin(a)*1.07,.032,.014,.018);
  stitch.rotation.y=-a-Math.PI/2;
}

const tray=group(scene,6.63,.06,.77);
const trayMat=clay(0x829458), lip=clay(0xb8c583), sand=clay(0xd2ac75), sandDark=clay(0xa78560);
oval(tray,trayMat,0,.19,0,1.02,.25,.73);
oval(tray,lip,0,.39,0,1.07,.115,.78);
oval(tray,sand,0,.452,0,.91,.062,.627);
for(let i=0;i<48;i++){
  const a=random()*Math.PI*2, r=Math.sqrt(random());
  oval(tray,i%3?sand:sandDark,Math.cos(a)*r*.87,.494,Math.sin(a)*r*.59,.044,.017,.036,a);
}
const gag=group(scene,6.06,.025,1.49);
const brown=clay(0x79503b);
strand(gag,brown,[[-.22,.10,0],[-.13,.13,-.02],[.07,.13,.04],[.21,.17,0],[.09,.26,-.03],[-.025,.24,.025],[.015,.32,0]],.092);
oval(gag,brown,.015,.32,0,.091,.091,.091);
const captions=[
  'У Кузи всего три важных дела.',
  'Первый: съесть всё. Проверить миску. На всякий случай.',
  'Второй: вздремнуть посреди коридора.',
  'Третий: сходить в туалет. Лоток почти пригодился.',
  'А теперь — играть!'
];
function solidText(text,x,y,size,color,align='center',family='Georgia'){
  titles.fillStyle=color;
  titles.textAlign=align;
  titles.textBaseline='middle';
  titles.font='700 '+size+'px '+family;
  titles.fillText(text,x,y);
}
function lettering(shot,t){
  titles.clearRect(0,0,1920,1080);
  const cream='#fff1d5';
  if(shot===0){
    solidText('КУЗЯ',960,88,84,cream);
    solidText('И ТРИ ВАЖНЫХ ДЕЛА',960,151,29,cream);
  } else if(shot<4){
    const labels=['','01   ПОЕСТЬ','02   ПОСПАТЬ','03   ЛОТОК'];
    solidText(labels[shot],100,111,37,cream,'left','Arial');
  } else {
    if(t>=32) solidText('ДОГОНЯЙ!',100,111,37,cream,'left','Arial');
  }
  titles.fillStyle='#392d34e8';
  titles.beginPath();
  titles.roundRect(305,969,1310,68,25);
  titles.fill();
  solidText(captions[shot],960,1003,32,cream,'center','Arial');
}

window.DUR=35;
window.render=t=>{
  const step=Math.floor(t*12)/12;
  const shot=t<4?0:t<12?1:t<20?2:t<27.75?3:4;
  const isSleep=shot===2, eating=shot<2;
  const inBath=t>=22.25&&t<28.65;
  const departing=t>=27.75&&t<31.15;
  const chasing=t>=31.15;
  const approaching=t>=20&&t<24.3;
  const running=departing||chasing;
  const gait=movingPhase(step,running);
  const breath=Math.sin(step*2.6);
  const settling=isSleep?smooth((step-12)/1.4):0;
  const nap=isSleep&&step>13;
  const bow=eating?Math.pow(Math.max(0,Math.sin((step-.3)*3.4)),2):0;
  const squat=shot===3?smooth((step-24.4)/.44)*(1-smooth((step-26.75)/.58)):0;

  let x=isSleep?-.68:0;
  let z=isSleep?.13:.12;
  let yaw=eating?.33:.1;
  if(shot===3){
    x=-.68+6.0*smooth((step-20)/4.45);
    z=.12+.63*smooth((step-22.4)/1.9);
    yaw=1.19*(1-smooth((step-23.4)/1.07))-.29*squat;
  } else if(running){
    const runDistance=clamp((step-27.75)/3.4);
    x=5.32-7.35*runDistance;
    z=.75-.54*smooth(runDistance*2);
    yaw=-1.18*smooth((step-27.75)/.27);
    if(chasing){
      const play=clamp((step-31.15)/3.55);
      x=-2.03-2.14*play+.34*Math.sin(play*Math.PI*2);
      z=.21+.46*Math.sin(play*Math.PI);
      yaw=-1.03+.29*Math.sin(play*Math.PI*2);
    }
  }
  const bounce=running?Math.max(0,Math.sin(gait))*.23:approaching?Math.max(0,Math.sin(gait))*.07:0;
  cat.position.set(x,(isSleep?.29:0)+bounce-.12*squat,z);
  cat.rotation.y=yaw;
  cat.rotation.z=running?-.13+Math.sin(gait)*.065:0;
  cat.scale.set(1+settling*.14,1-settling*.23-squat*.12,1+settling*.13);
  torso.scale.set(1.06+breath*.012,1.04,.89);
  chest.scale.x=.69+breath*.018;
  head.position.y=2.01-.32*settling-.25*bow+breath*.022;
  head.position.z=.31+.29*bow+.13*settling;
  head.rotation.x=.42*bow+.14*settling-.09*bounce;
  head.rotation.y=inBath?.16:0;
  head.rotation.z=settling*.13;
  muzzle.scale.y=1+(bow>.65?.045*Math.sin(step*29):0);
  tongue.visible=eating&&bow>.65;
  eyes.visible=!(nap||step%4.5>4.34);
  lids.visible=!eyes.visible;
  tail.rotation.y=.12*Math.sin(step*2)+.20*settling+(inBath?.59:0);
  tail.rotation.z=.10*Math.sin(step*2.6)-.13*settling+(running?.37:0);
  for(let i=0;i<paws.length;i++){
    const stride=running||approaching?Math.sin(gait+i*Math.PI):0;
    paws[i].position.y=.33+Math.max(0,stride)*(running?.29:.13);
    paws[i].position.z=.62+stride*(running?.47:.22);
  }
  bowl.visible=eating;
  bowl.position.set(1.18,0,1.03);
  const remaining=Math.max(0,9-Math.floor((shot===0?step*.8:3+(step-4)*1.65)));
  treats.forEach((item,i)=>item.visible=i<remaining);
  cushion.scale.y=1.04-.14*settling;
  gag.visible=t>=26.55;
  toy.visible=t>=28.65;
  const roll=clamp((step-28.65)/6.15);
  const swat=smooth((step-32.75)/.48);
  toy.position.set(-.35-4.36*smooth(roll)-.42*swat,.285+Math.abs(Math.sin(roll*14))*.28*(1-roll)+Math.sin(swat*Math.PI)*.32,1.43-.58*roll+.26*swat);
  toy.rotation.z=roll*17+swat*2;
  const reach=smooth((step-32.5)/.20)*(1-smooth((step-32.84)/.29));
  paws[0].position.y+=.19*reach;
  paws[0].position.z+=.34*reach;

  if(t<12){
    camera.position.set(shot===0?1.15:-.91,3.02,8.05);
    camera.lookAt(.13,1.56,.05);
  } else if(t<20){
    const dolly=smooth((t-12)/8);
    camera.position.set(-.18+dolly*.62,2.72,7.65-dolly*.58);
    camera.lookAt(-.77,1.31,.02);
  } else if(t<22.25){
    camera.position.set(.28,3.01,8.7);
    camera.lookAt(1.31,1.49,0);
  } else if(t>=26.55&&t<27.75){
    camera.position.set(6.65,2.77,5.15);
    camera.lookAt(6.20,.77,1.26);
  } else if(inBath){
    camera.position.set(5.68,3.24,7.18);
    camera.lookAt(5.44,1.43,.17);
  } else {
    const follow=Math.min(-.17,x+.28);
    camera.position.set(follow-.73,2.62,7.58);
    camera.lookAt(follow-.31,1.32,.24);
  }
  renderer.render(scene,camera);
  lettering(shot,t);
};
function movingPhase(time,running) {
  return time*(running?14.7:10.2);
}
window.READY=true;
window.render(0);
