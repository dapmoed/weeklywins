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
Object.assign(key.shadow.camera,{left:-6,right:6,top:5,bottom:-5,near:.3,far:18});
key.shadow.normalBias=.025;
key.shadow.radius=3;
key.shadow.bias=-.00016;
scene.add(key);
const edge = new T.DirectionalLight(0xc2d8ff,1.7);
edge.position.set(4,4,-3);
scene.add(edge);

const floor=clay(0xba755e,.9,.065), wall=clay(0xc38471,.93,.04);
box(scene,floor,0,-.16,0,32,.3,27);
box(scene,wall,0,5,-4.4,32,12,.4);

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

const cushion=group(scene,0,.15,-.06);
const fabric=clay(0xc68549,.95,.1);
oval(cushion,fabric,0,0,0,1.82,.29,1.14);
const seam=clay(0xe6a968,.92);
for(let i=0;i<52;i++){
  const a=i*(Math.PI*2/52);
  const stitch=oval(cushion,seam,Math.cos(a)*1.71,.095,Math.sin(a)*1.07,.032,.014,.018);
  stitch.rotation.y=-a-Math.PI/2;
}

const tray=group(scene,1.33,.08,.25);
const trayMat=clay(0x829458), lip=clay(0xb8c583), sand=clay(0xd2ac75), sandDark=clay(0xa78560);
oval(tray,trayMat,0,.19,0,1.02,.25,.73);
oval(tray,lip,0,.39,0,1.07,.115,.78);
oval(tray,sand,0,.452,0,.91,.062,.627);
for(let i=0;i<48;i++){
  const a=random()*Math.PI*2, r=Math.sqrt(random());
  oval(tray,i%3?sand:sandDark,Math.cos(a)*r*.87,.494,Math.sin(a)*r*.59,.044,.017,.036,a);
}
const gag=group(scene,.11,.07,1.13);
const brown=clay(0x79503b);
strand(gag,brown,[[-.22,.10,0],[-.13,.13,-.02],[.07,.13,.04],[.21,.17,0],[.09,.26,-.03],[-.025,.24,.025],[.015,.32,0]],.092);
oval(gag,brown,.015,.32,0,.091,.091,.091);
const screen=group(scene);
const panel=clay(0xa65346), trim=clay(0xdbad79);
for(const x of [-.62,0,.62]){
  const section=group(screen,x,0,x===0?0:-.15);
  section.rotation.y=-x*.5;
  box(section,panel,0,1.05,0,.59,2,.10);
  for(const edgeX of [-.29,.29]) box(section,trim,edgeX,1.06,.06,.042,2.12,.043);
  for(const y of [.14,2.02]) box(section,trim,0,y,.06,.6,.041,.043);
}

const palette=[
  [0x956247,0x9c6651],[0xae6957,0xaf7969],[0x847250,0xa09264],
  [0x66596e,0x8e778b],[0x785646,0xa77861]
];
const captions=[
  'У Кузи всего три важных дела.',
  'Первый: съесть всё. Проверить миску. На всякий случай.',
  'Второй: восстановить силы. Немедленно.',
  'Третий: воспользоваться лотком. По крайней мере, таков был план.',
  'Идеально. Почти.'
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
    solidText('ПЛАН ВЫПОЛНЕН.',960,78,59,cream);
    if(t>=32) solidText('ПОЧТИ.',960,130,39,'#ffe0a3');
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
  const shot=t<4?0:t<12?1:t<20?2:t<30?3:4;
  const isSleep=shot===2, isTray=shot===3, eating=shot<2;
  const start=[0,4,12,20,30][shot];
  const local=step-start;
  floor.color.setHex(palette[shot][0]);
  wall.color.setHex(palette[shot][1]);
  scene.background=wall.color.clone();
  const breath=Math.sin(step*2.6);
  const walking=isTray&&local<3.5;
  const settling=isSleep?smooth(local/1.4):0;
  const nap=isSleep&&local>1;
  const bow=eating?Math.pow(Math.max(0,Math.sin((local-.3)*3.4)),2):0;
  const lick=eating&&bow>.65;
  const glance=isTray?smooth((local-7.5)*1.4):0;
  cat.position.set(isTray?-.82+smooth(local/3.5)*.39:shot===4?-.32:0,isSleep?.29:0,0);
  cat.rotation.y=isTray?.39*(1-glance)-glance*.13:shot===4?-.12:.10;
  cat.scale.set(1+settling*.14,1-settling*.23,1+settling*.13);
  torso.scale.set(1.06+breath*.012,1.04,.89);
  chest.scale.x=.69+breath*.018;
  head.position.y=2.01-.32*settling-.25*bow+(walking?Math.sin(local*12)*.04:breath*.022);
  head.position.z=.31+.29*bow+.13*settling;
  head.rotation.x=.42*bow+.14*settling;
  head.rotation.y=glance*.29;
  head.rotation.z=shot===4?.05*Math.sin(local*2):settling*.13;
  muzzle.scale.y=1+(lick?.045*Math.sin(step*29):0);
  tongue.visible=lick;
  const blink=step%4.5>4.34;
  eyes.visible=!(nap||blink);
  lids.visible=!eyes.visible;
  tail.rotation.y=.12*Math.sin(step*2)+.20*settling+(isTray?.59:0);
  tail.rotation.z=.10*Math.sin(step*2.6)-.13*settling;
  for(let i=0;i<paws.length;i++){
    const stride=walking?Math.sin(local*10+i*Math.PI):0;
    paws[i].position.y=.33+Math.max(0,stride)*.13;
    paws[i].position.z=.62+stride*.18;
  }
  bowl.visible=eating||shot===4;
  bowl.position.set(shot===4?1.37:1.20,0,shot===4?.91:1.02);
  const remaining=shot===4?0:Math.max(0,9-Math.floor(local*(shot===0?1.2:2.1)));
  treats.forEach((item,i)=>item.visible=i<remaining);
  cushion.visible=isSleep;
  cushion.scale.y=1.04-.14*settling;
  tray.visible=isTray;
  gag.visible=isTray&&local>7.4;
  screen.visible=isTray&&local>=3.45&&local<7.7;
  const slide=smooth((local-3.45)/.54);
  const withdraw=smooth((local-7.05)/.65);
  screen.position.set(-.23-(1-slide)*4.7+withdraw*5.9,.06,1.63);
  const elapsed=t-start;
  const angle=[.86,-1.16,.65,1.12,-.46][shot]+.2*smooth(elapsed/6);
  const distance=[7.5,6.85,6.35,7.6,7.25][shot]-.25*smooth(elapsed/8);
  camera.position.set(angle,[3.04,2.69,2.58,3.6,3.02][shot],distance);
  camera.lookAt(isTray?.28:shot===4?.1:0,isSleep?1.3:1.46,.23);
  renderer.render(scene,camera);
  lettering(shot,t);
};
window.READY=true;
window.render(0);
