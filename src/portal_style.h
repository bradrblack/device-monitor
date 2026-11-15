// Look of the Wi-Fi setup portal (WiFiManager's pages). Added after WiFiManager's
// own stylesheet, so these rules win. Same palette as the board's web page,
// light or dark to match the phone.
//
// The script turns off autocorrect, auto-capitalisation, spell check and
// autofill on every text field (WiFiManager's password box loses them when
// "Show Password" turns it into a text box), makes each row of the network
// list tappable across its whole width, spells out that blank network fields
// keep the saved network (WiFiManager shows it, and "********", as grey
// placeholders that look like filled-in values), requires a network name on a board that
// has none saved, and replaces WiFiManager's terse "Saved" pages with what
// happens next.
#pragma once

const char PORTAL_HEAD[] = R"PORTAL(<style>
:root{--bg:#f4f5f7;--card:#fff;--fg:#1c2330;--dim:#667085;--line:#d8dce3;--acc:#1f6feb;--ok:#1a8f4c;--bad:#d1242f}
@media(prefers-color-scheme:dark){:root{--bg:#12151b;--card:#1c212b;--fg:#e6e9ef;--dim:#98a2b3;--line:#333b49;--acc:#4c8dff;--ok:#4cc38a;--bad:#ff7b72}.q{filter:invert(1)}}
*{box-sizing:border-box}
body,body.invert{margin:0;padding:24px 16px;background:var(--bg);color:var(--fg);text-align:left;font:16px/1.45 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif}
.wrap{display:block;max-width:420px;min-width:0;margin:0 auto;padding:22px 20px 12px;background:var(--card);border:1px solid var(--line);border-radius:14px;box-shadow:0 2px 10px rgba(0,0,0,.06)}
.wrap>br,form>br{display:none}
h1{font-size:22px;margin:0;color:var(--fg)}
h1:before{content:"";display:inline-block;width:12px;height:12px;margin-right:9px;border-radius:50%;background:#a541d6;box-shadow:0 0 0 4px rgba(165,65,214,.18);vertical-align:2px}
h3{margin:2px 0 18px;font-size:14px;font-weight:500;color:var(--dim)}
hr{border:0;border-top:1px solid var(--line);margin:18px 0 6px}
form{margin:0 0 10px}
div,input,select{margin:0}
button,input[type=submit]{display:block;width:100%;padding:13px 16px;font:inherit;font-size:16px;font-weight:600;line-height:1.2;color:var(--fg);background:var(--bg);border:1px solid var(--line);border-radius:10px;cursor:pointer;transition:border-color .15s,transform .06s}
button:hover{border-color:var(--acc)}
button:active{transform:scale(.98);opacity:.85!important}
form[action='/wifi'] button,form[method='POST']>button[type=submit]{background:var(--acc);border-color:var(--acc);color:#fff}
form[action='/wifi'] button{margin-top:4px}
form[action='/wifi'] button:after{content:" \203A"}
button.D{background:var(--bad);border-color:var(--bad);color:#fff}
form[method='POST']>button[type=submit]{margin-top:20px}
label{display:block;margin:14px 0 5px;font-size:13px;font-weight:600;color:var(--dim)}
input{display:block;width:100%;padding:12px;font:inherit;font-size:16px;color:var(--fg);background:var(--bg);border:1px solid var(--line);border-radius:10px}
input:focus{outline:none;border-color:var(--acc);box-shadow:0 0 0 3px rgba(31,111,235,.2)}
input:disabled{opacity:.5}
input[type=checkbox]{display:inline-block;width:18px;height:18px;margin:12px 8px 0 0;vertical-align:-4px;accent-color:var(--acc)}
input[type=checkbox]+label{display:inline;margin:0;font-weight:500}
.msg,body.invert .msg{margin:16px 0 8px;padding:12px 14px;font-size:14px;color:var(--fg);background:var(--bg);border:1px solid var(--line);border-left:4px solid var(--dim);border-radius:10px}
.msg.S{border-left-color:var(--ok)}.msg.D{border-left-color:var(--bad)}.msg.P{border-left-color:var(--acc)}
.note{margin:0 0 4px;padding:10px 12px;font-size:14px;color:var(--fg);background:var(--bg);border:1px solid var(--line);border-left:4px solid var(--acc);border-radius:10px}
input::placeholder{color:var(--dim);opacity:.7;font-style:italic}
.net{display:flex;align-items:center;gap:8px;padding:13px 4px;border-bottom:1px solid var(--line);cursor:pointer}
.net:first-of-type{border-top:1px solid var(--line)}
.net a{flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;color:var(--fg);font-weight:600;text-decoration:none}
.net .q{float:none;margin:0;padding:0;min-width:0;color:var(--dim);font-size:13px}
dt{margin-top:8px;font-size:13px;color:var(--dim)}dd{margin:0}
a{color:var(--acc)}
</style><script>
document.addEventListener('DOMContentLoaded',function(){
var all=function(s){return Array.prototype.slice.call(document.querySelectorAll(s))};
all('input').forEach(function(i){
if(/^(checkbox|radio|file|hidden)$/.test(i.type))return;
i.setAttribute('autocapitalize','none');i.setAttribute('autocorrect','off');
i.setAttribute('spellcheck','false');i.setAttribute('autocomplete','off');
});
var s=document.getElementById('s'),p=document.getElementById('p');
if(s&&p){
var cur=s.placeholder;
if(cur){
var n=document.createElement('div');n.className='note';
n.appendChild(document.createTextNode('Saved network: '));
var k=document.createElement('strong');k.textContent=cur;n.appendChild(k);
n.appendChild(document.createTextNode('. To keep it, leave the network and password blank.'));
s.form.insertBefore(n,s.form.firstChild);
s.placeholder=cur+' (saved)';
p.placeholder='saved - type to replace';
s.form.addEventListener('submit',function(){if(s.value.trim()==cur&&!p.value)s.value='';});
}else{s.required=true;s.placeholder='pick a network above';p.placeholder='blank for an open network';}
}
var t=document.title,m=document.querySelector('.msg'),b=document.querySelector("form[action='/']");
if(m&&/^Credentials saved/.test(t)){
m.className='msg P';
m.innerHTML='<strong>Saved. The board is joining the network now.</strong><br>If it connects, it restarts and this setup Wi-Fi disappears in about 20 seconds. Close this window and rejoin your usual network.<br><br>If this setup Wi-Fi is still there after a minute, the join failed: reconnect to it and check the network and password.';
if(b)b.style.display='none';
}else if(m&&/^(Settings|Setup) saved/.test(t)){
m.className='msg S';
m.innerHTML='<strong>Saved.</strong><br>The setup portal is closing and the board carries on with its current network (it restarts first if you changed its name or password). You can close this window.';
if(b)b.style.display='none';
}
all('.wrap>div').forEach(function(d){
var a=d.querySelector('a[onclick]');if(!a)return;
d.className+=' net';d.onclick=function(e){if(e.target!==a)a.click()};
});
});
</script>)PORTAL";
