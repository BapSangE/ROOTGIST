// use_figma로 실행: 파일 31VNt2AvSPGTTCaonuFgnS, 페이지 「홈·탐색 A안」(9:42)에 탐색·모델 트렌딩·새로 나옴 두 화면을 만든다.
// 2026-10-31 Starter 요금제 호출 한도로 못 돌린 마지막 단계. 노드 id는 README 참고.
const FAM='Noto Sans KR';
await Promise.all(['Regular','Medium','Bold'].map(s=>figma.loadFontAsync({family:FAM,style:s})));
const hex=h=>{h=h.replace('#','');return{r:parseInt(h.slice(0,2),16)/255,g:parseInt(h.slice(2,4),16)/255,b:parseInt(h.slice(4,6),16)/255}};
const solid=h=>[{type:'SOLID',color:hex(h)}];
const W={r:'Regular',m:'Medium',b:'Bold'};
const C={ink:'1F1F1C',body:'3A3A36',mute:'76766F',faint:'9A9A93',card:'F4F4F2',div:'E3E3E0'};
const page=await figma.getNodeByIdAsync('9:42');await figma.setCurrentPageAsync(page);
const [chipSet,sbC,tabV,bmC,infoC,segV]=await Promise.all(['2:44','9:69','9:96','9:116','9:63','9:133'].map(id=>figma.getNodeByIdAsync(id)));
function T(str,o={}){const t=figma.createText();t.fontName={family:FAM,style:W[o.w||'r']};t.characters=str;t.fontSize=o.s||14;t.fills=solid(o.c||C.ink);if(o.lh)t.lineHeight={unit:'PIXELS',value:o.lh};if(o.ls)t.letterSpacing={unit:'PIXELS',value:o.ls};if(o.name)t.name=o.name;return t;}
function A(dir,o={}){const f=figma.createAutoLayout(dir);f.fills=o.fill?solid(o.fill):[];if(o.gap!=null)f.itemSpacing=o.gap;const p=o.pad||[0,0,0,0];f.paddingTop=p[0];f.paddingRight=p[1];f.paddingBottom=p[2];f.paddingLeft=p[3];if(o.r)f.cornerRadius=o.r;if(o.name)f.name=o.name;if(o.align)f.counterAxisAlignItems=o.align;return f;}
function add(p,c,fill){p.appendChild(c);if(fill){if(c.type==='TEXT')c.textAutoResize='HEIGHT';c.layoutSizingHorizontal='FILL';}return c;}
function chip(tone,label){const v=chipSet.children.find(x=>x.name==='tone='+tone);if(!v)throw new Error('no tone '+tone);const i=v.createInstance();i.setProperties({'label#2:0':label});return i;}
function top(f){f.strokes=solid(C.div);f.strokeAlign='INSIDE';f.strokeTopWeight=1;f.strokeBottomWeight=0;f.strokeLeftWeight=0;f.strokeRightWeight=0;}
function card(p,name){const wrap=A('VERTICAL',{pad:[0,16,0,16],name:name+' (여백 16)'});add(p,wrap,true);const c=A('VERTICAL',{fill:C.card,r:22,name});add(wrap,c,true);c.clipsContent=true;return c;}
function sp(p,h){const s=figma.createFrame();s.name='↕'+h;s.resize(10,h);s.fills=[];add(p,s,true);return s;}
function underline(p,labels,sel){const u=A('HORIZONTAL',{pad:[0,20,0,20],gap:22,name:'밑줄 탭'});u.strokes=solid(C.div);u.strokeAlign='INSIDE';u.strokeTopWeight=0;u.strokeLeftWeight=0;u.strokeRightWeight=0;u.strokeBottomWeight=1;add(p,u,true);
 for(const l of labels){const on=l===sel;const t=A('VERTICAL',{pad:[10,0,9,0]});if(on){t.strokes=solid(C.ink);t.strokeAlign='INSIDE';t.strokeTopWeight=0;t.strokeLeftWeight=0;t.strokeRightWeight=0;t.strokeBottomWeight=2;}add(u,t);add(t,T(l,{w:on?'b':'m',s:15,c:on?C.ink:C.faint}));}return u;}
function info(p,str,pt){const r=A('HORIZONTAL',{pad:[pt??12,20,0,20],gap:6,name:'안내'});add(p,r,true);const iw=A('VERTICAL',{pad:[2,0,0,0]});add(r,iw);const i=infoC.createInstance();i.rescale(14/24);add(iw,i);add(r,T(str,{s:12.5,lh:18,c:C.mute}),true);}
function screen(name,x){const s=A('VERTICAL',{fill:'FFFFFF',name});s.resize(402,100);s.primaryAxisSizingMode='AUTO';s.counterAxisSizingMode='FIXED';s.x=x;s.y=0;s.clipsContent=true;add(s,sbC.createInstance());
 const tb=A('HORIZONTAL',{pad:[0,20,0,20],align:'CENTER',name:'표제'});tb.resize(402,56);tb.primaryAxisSizingMode='FIXED';tb.counterAxisSizingMode='FIXED';add(s,tb,true);add(tb,T('탐색',{w:'b',s:34,lh:40,ls:-1}));
 const sg=A('VERTICAL',{pad:[12,20,4,20],name:'칸 전환'});add(s,sg,true);add(sg,segV.createInstance(),true);sp(s,12);return s;}
// 통일 순서: 칩 → 모델 이름 → 설명 → 메타 → 변형. 순위는 모든 행이 같은 자리(1위만 진하게)
function modelRow(c,m,i,ranked){const r=A('HORIZONTAL',{gap:10,pad:[14,12,14,ranked?18:20],name:m[1]});if(i)top(r);add(c,r,true);
 if(ranked){const rk=A('HORIZONTAL');rk.counterAxisAlignItems='BASELINE';add(r,rk);add(rk,T(String(i+1),{w:'b',s:14,lh:22,c:i?C.faint:C.ink}));add(rk,T('위',{w:'m',s:11,lh:22,c:i?C.faint:C.ink}));rk.resize(28,22);rk.primaryAxisSizingMode='FIXED';}
 const col=A('VERTICAL');add(r,col,true);const h=A('HORIZONTAL',{gap:6,align:'CENTER'});add(col,h);add(h,chip('A-neutral',m[0]));if(m[5])add(h,T(m[5],{s:12,c:C.faint}));
 sp(col,6);add(col,T(m[1],{w:'m',s:15.5,lh:22,ls:-0.3}),true);add(col,T(m[2],{s:13,lh:19,c:C.mute}),true);if(m[3]){sp(col,6);add(col,T(m[3],{s:12,lh:17,c:C.faint}),true);}
 if(m[4]){sp(col,8);add(col,T(m[4],{w:'m',s:12.5,lh:16,c:C.body}));}
 add(r,bmC.createInstance());}

let scr=screen('탐색 · 모델 · 트렌딩 · A안',2300);
underline(scr,['트렌딩','새로 나옴'],'트렌딩');
info(scr,'요즘 Hugging Face에서 주목받는 모델이에요. 순서는 Hugging Face의 트렌딩 순위예요.',14);sp(scr,14);
let c=card(scr,'트렌딩 목록');
[['DeepSeek','DeepSeek-V4.1-Flash-1017','7,632억 파라미터 이미지·텍스트 이해 모델','MIT · 좋아요 4,024 · 다운로드 15만','변형 2개 ›'],
 ['Nanbeige','Nanbeige4.3-33B','331억 파라미터 텍스트 생성 모델','Apache-2.0 · 좋아요 799 · 다운로드 1.2만','변형 1개 ›'],
 ['Liquid AI','LFM3-1.7B','17억 파라미터 텍스트 생성 모델','개별 라이선스 · 좋아요 575 · 다운로드 2.4만','변형 4개 ›'],
 ['NVIDIA','NVIDIA-Nemotron-3.5-Transcribe-30B-A4B','337억 파라미터 음성 인식 모델','개별 라이선스 · 좋아요 507 · 다운로드 1.6만',null],
 ['Baidu','Unlimited-OCR-2','33억 파라미터 이미지·텍스트 이해 모델','MIT · 좋아요 457 · 다운로드 2.4만',null],
 ['Mistral AI','Mistral-Large-4-1T-A52B','이미지·텍스트 이해 모델','개별 라이선스 · 좋아요 1,353 · 다운로드 1,239',null],
 ['Lightricks','LTX-2.5','이미지 → 영상 생성 모델','개별 라이선스 · 좋아요 9,977 · 다운로드 234만',null],
 ['RecursiveSI','flint','398억 파라미터 텍스트 생성 모델','Apache-2.0 · 좋아요 1,262 · 다운로드 1.9만','변형 1개 ›'],
 ['Black Forest Labs','flux-3-image-klein','55억 파라미터 이미지 편집 모델','개별 라이선스 · 좋아요 773 · 다운로드 14만','변형 1개 ›'],
 ['XHToken','Spark-X2.6-4B','41억 파라미터 텍스트 생성 모델','Apache-2.0 · 좋아요 923 · 다운로드 1.3만','변형 1개 ›']].forEach((m,i)=>modelRow(c,m,i,true));
const mo=A('HORIZONTAL',{pad:[14,16,14,16]});mo.primaryAxisAlignItems='CENTER';top(mo);add(c,mo,true);add(mo,T('11~25위 더 보기',{w:'m',s:13.5,c:C.body}));
sp(scr,24);add(scr,tabV.createInstance());
const tr=scr;

scr=screen('탐색 · 모델 · 새로 나옴 · A안',2760);
underline(scr,['트렌딩','새로 나옴'],'새로 나옴');
info(scr,'최근 2주 안에 공개된 모델을 새것부터 보여 줘요. Hugging Face 트렌딩 100위 안에 든 모델만 모았어요.',14);sp(scr,14);
c=card(scr,'새로 나옴 목록');
[['Pika-Labs','Pika-H3-Flex','331억 파라미터 이미지 → 영상 생성 모델',null,null,'2일 전 공개 · 트렌딩 13위'],
 ['sensenova','SenseNova-Loop-9B-Preview','97억 파라미터 이미지·텍스트 이해 모델',null,null,'3일 전 공개 · 21위'],
 ['inclusionAI','Ling-3.1-flash-1019','5,721억 파라미터 텍스트 생성 모델',null,null,'4일 전 공개 · 19위'],
 ['Baidu','Unlimited-OCR-2','33억 파라미터 이미지·텍스트 이해 모델',null,null,'5일 전 공개 · 5위'],
 ['maya-research','maya2-native','25억 파라미터 음성 합성 모델',null,null,'5일 전 공개 · 17위'],
 ['gugujiji','novel-humanize-4b','40억 파라미터 텍스트 생성 모델',null,null,'6일 전 공개 · 25위'],
 ['Nanbeige','Nanbeige4.3-33B','331억 파라미터 텍스트 생성 모델',null,'변형 1개 ›','7일 전 공개 · 2위'],
 ['Diffuspace','Clover-35B-A3B-Preview','347억 파라미터 텍스트 생성 모델',null,null,'7일 전 공개 · 15위']].forEach((m,i)=>modelRow(c,m,i,false));
sp(scr,24);add(scr,tabV.createInstance());
// 홈 모델 다운로드 수 표기 맞춤(countKo: 10만 이상은 소수점 없음)
const home=await figma.getNodeByIdAsync('10:53');
for(const t of home.findAll(n=>n.type==='TEXT'&&n.characters.includes('14.6만'))){await figma.loadFontAsync(t.fontName);t.characters=t.characters.replace('14.6만','15만');}
await tr.screenshot({scale:0.4});await scr.screenshot({scale:0.4});
return {trending:tr.id,fresh:scr.id};
