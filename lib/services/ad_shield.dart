/// Best-effort ad suppression for pages loaded in a WebView (embed players,
/// stream pages, download pages). A WebView can't filter network requests, so
/// this works in two ways:
///  * [isAdUrl]: known ad-network hosts/paths are refused in the navigation
///    delegate (also for iframes and sub-frames).
///  * [adShieldJs]: a script that removes pop-ups, click-catching overlays and
///    banner / video / gif ad blocks while never touching the real player.
class AdShield {
  static final _adHosts = RegExp(
    r'(^|\.)('
    r'doubleclick\.net|googlesyndication\.com|googleadservices\.com|'
    r'imasdk\.googleapis\.com|2mdn\.net|googletagservices\.com|'
    r'adsafeprotected\.com|moatads\.com|serving-sys\.com|innovid\.com|'
    r'spotxchange\.com|springserve\.com|smartadserver\.com|'
    r'adservice\.google\.[a-z.]+|adnxs\.com|adsterra\.com|'
    r'propellerads\.com|popads\.net|popcash\.net|popunder\.net|'
    r'exoclick\.com|exosrv\.com|juicyads\.com|trafficjunky\.net|'
    r'clickadu\.com|hilltopads\.net|adcash\.com|revcontent\.com|'
    r'taboola\.com|outbrain\.com|mgid\.com|criteo\.com|'
    r'pubmatic\.com|rubiconproject\.com|openx\.net|adform\.net|'
    r'onclickads\.net|onclkds\.com|profitablecpmrate\.com|'
    r'highperformanceformat\.com|effectivegatecpm\.com|'
    r'adsco\.re|a-ads\.com|ad-maven\.com|admaven\.com|'
    r'monetag\.com|richpush\.co|pushwoosh\.com|'
    r'yllix\.com|ero-advertising\.com|bidvertiser\.com|'
    r'tsyndicate\.com|trafmag\.com|syndication\.exdynsrv\.com|'
    r'ads\.[a-z0-9-]+\.[a-z.]+|adserver\.[a-z0-9-]+\.[a-z.]+'
    r')$',
    caseSensitive: false,
  );

  static final _adPath = RegExp(
    r'/(ads?|adserver|advert|banner|popunder|popup|pop-under)[/_.-]|[?&](ad|ads|adid)=',
    caseSensitive: false,
  );

  static bool isAdUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return false;
    if (_adHosts.hasMatch(uri.host)) return true;
    // Only treat path hints as ads on sub-frames of third-party hosts; the
    // caller decides whether that applies.
    return false;
  }

  /// Looser check used only for sub-frames / sub-resources.
  static bool isAdSubframe(String url) =>
      isAdUrl(url) || _adPath.hasMatch(Uri.tryParse(url)?.path ?? '');

  /// Injected after every page start / finish. Safe to run repeatedly.
  static const adShieldJs = r"""
(function(){
  try{
    if(window.__dwShield){window.__dwShield();return}
    var BAD=/(doubleclick|googlesyndication|googleadservices|googletagservices|imasdk|2mdn\.net|adnxs|adsterra|propeller|popads|popcash|exoclick|exosrv|juicyads|trafficjunky|clickadu|hilltopads|adcash|taboola|outbrain|mgid|criteo|onclickads|onclkds|profitablecpmrate|highperformanceformat|effectivegatecpm|a-ads|admaven|ad-maven|monetag|richpush|bidvertiser|tsyndicate|exdynsrv|adsafeprotected|moatads|serving-sys|innovid|spotxchange|springserve|smartadserver|\/ads?[\/_.-]|adserver|popunder)/i;
    // Text that only appears on ad UI ("Close ad", "Skip ad" ...).
    var AD_TXT=/^(close ad|skip ads?|skip ad in.*|ad closes in.*|advertisement|sponsored)$/i;
    var SEL='[id^="ad-"],[id^="ad_"],[id$="-ad"],[id$="_ad"],[id*="advert" i],'+
            '[class^="ad-"],[class^="ad_"],[class*=" ad-"],[class*=" ad_"],[class*="advert" i],'+
            '[class*="popunder" i],[class*="sponsor" i],'+
            '.ima-ad-container,[id*="ima-ad"],[class*="adContainer"],[class*="ad-container"],'+
            '.videoAdUi,.videoAdUiSkipContainer,[class*="ad-overlay"],[class*="adOverlay"],'+
            'ins.adsbygoogle,[data-ad],[data-ad-slot],[data-adsbygoogle-status]';
    function hasPlayer(el){
      if(!el||el.nodeType!==1)return false;
      var t=el.tagName;
      if(t==='VIDEO'||t==='AUDIO')return true;
      return !!(el.querySelector&&el.querySelector('video,audio'));
    }
    function isPlayerFrame(f){
      var r=f.getBoundingClientRect();
      return r.width*r.height>=0.35*innerWidth*innerHeight;
    }
    function kill(el){try{el.style.setProperty('display','none','important');el.remove()}catch(e){}}
    function hide(el){try{el.style.setProperty('display','none','important')}catch(e){}}

    // ---- video ad overlays (IMA / VAST players): "Close ad", "Learn more",
    //      "Replay" end cards. Presses the close/skip button, hides the ad
    //      layer, silences the ad and lets the real stream continue.
    function resume(doc,box){
      setTimeout(function(){
        try{
          var all=doc.querySelectorAll('video');
          for(var q=0;q<all.length;q++){
            var v=all[q];
            if(box&&box.contains(v))continue;
            if(v.paused&&!v.ended)v.play();
          }
        }catch(e){}
      },400);
    }
    function handleAd(doc,win,el){
      el.__dwDone=1;
      var box=null,cur=el,vw=win.innerWidth||1,vh=win.innerHeight||1;
      for(var d=0;d<8&&cur&&cur.parentElement&&cur!==doc.body;d++){
        var cs=win.getComputedStyle(cur);
        if(cs.position==='fixed'||cs.position==='absolute'){
          var r=cur.getBoundingClientRect();
          if(r.width*r.height>=0.2*vw*vh){box=cur;break}
        }
        cur=cur.parentElement;
      }
      try{if(el.click)el.click()}catch(e){}
      if(box){
        var vids=box.querySelectorAll('video,audio');
        for(var v=0;v<vids.length;v++){try{vids[v].muted=true;vids[v].pause()}catch(e){}}
        hide(box);
      }
      resume(doc,box);
    }
    function adUi(doc){
      var win=doc.defaultView||window;
      var nodes=doc.querySelectorAll('button,div,span,a,p,li,[role=button],[aria-label]');
      var hits=[];
      for(var i=0;i<nodes.length&&i<5000;i++){
        var e=nodes[i];
        if(e.__dwDone)continue;
        var lab=(e.getAttribute&&e.getAttribute('aria-label'))||'';
        var t='';
        if(e.children.length<=2){
          t=(e.textContent||'').replace(/\s+/g,' ').trim();
          if(t.length>28)t='';
        }
        if((t&&AD_TXT.test(t))||/^(close|skip) ad/i.test(lab))hits.push(e);
      }
      for(var h=0;h<hits.length;h++)handleAd(doc,win,hits[h]);
    }
    function frameDocs(doc){
      var out=[],fs=doc.querySelectorAll('iframe');
      for(var i=0;i<fs.length;i++){
        try{var d=fs[i].contentDocument;if(d&&d.body)out.push(d)}catch(e){}
      }
      return out;
    }

    function sweep(){
      try{
        // 1. ad iframes / scripts / images / gifs / videos from ad hosts
        var list=document.querySelectorAll('iframe,img,video,source,embed,object,script,link');
        for(var i=0;i<list.length;i++){
          var n=list[i];
          var u=n.src||n.href||n.getAttribute('data-src')||'';
          if(!u||!BAD.test(u))continue;
          if(n.tagName==='VIDEO'&&hasPlayer(n)&&!BAD.test(n.currentSrc||u))continue;
          if(n.tagName==='IFRAME'&&isPlayerFrame(n)&&!/doubleclick|googlesyndication|adsterra|popads|exoclick|imasdk/i.test(u))continue;
          kill(n);
        }
        // 2. class / id based ad containers (never ones holding the player)
        var c=document.querySelectorAll(SEL);
        for(var j=0;j<c.length;j++){
          var e=c[j];
          if(hasPlayer(e)||e.contains(document.activeElement))continue;
          var r=e.getBoundingClientRect();
          if(r.width*r.height>0.6*innerWidth*innerHeight&&!/fixed|absolute|sticky/.test(getComputedStyle(e).position))continue;
          kill(e);
        }
        // 3. fixed / absolute floating layers: banners, gif/video ads and
        //    invisible click-catchers sitting above the player
        var all=document.body?document.body.getElementsByTagName('*'):[];
        for(var k=0;k<all.length&&k<2500;k++){
          var x=all[k];
          if(x.tagName==='VIDEO'||x.tagName==='AUDIO'||x.tagName==='SCRIPT'||x.tagName==='STYLE')continue;
          var cs=getComputedStyle(x);
          if(cs.position!=='fixed'&&cs.position!=='absolute'&&cs.position!=='sticky')continue;
          var z=parseInt(cs.zIndex,10);
          if(!(z>=100))continue;
          if(hasPlayer(x))continue;
          if(x.closest&&x.closest('video,[class*="jw"],[class*="vjs"],[class*="plyr"],[class*="player" i],[id*="player" i]'))continue;
          var b=x.getBoundingClientRect();
          if(b.width<30||b.height<20)continue;
          var big=b.width>=0.6*innerWidth&&b.height>=0.6*innerHeight;
          var media=x.tagName==='IMG'||x.tagName==='IFRAME'||x.querySelector('img,iframe,video[muted]');
          var hasText=(x.innerText||'').trim().length>0;
          if(big&&!hasText&&!x.querySelector('button,input,svg')){kill(x);continue}
          if(media&&!big){kill(x);continue}
        }
        // 4. video ad overlay UI in the page and in same-origin frames
        adUi(document);
        var fr=frameDocs(document);
        for(var f=0;f<fr.length;f++)adUi(fr[f]);
      }catch(e){}
    }
    window.__dwShield=sweep;
    // pop-ups, new tabs, redirects triggered by scripts
    window.open=function(){return null};
    document.addEventListener('click',function(ev){
      var a=ev.target&&ev.target.closest?ev.target.closest('a[target=_blank],a[target=_new]'):null;
      if(a){ev.preventDefault();ev.stopPropagation()}
    },true);
    var st=document.createElement('style');
    st.textContent='ins.adsbygoogle,[id^="google_ads"],[id^="div-gpt-ad"],.ima-ad-container,.videoAdUi,iframe[src*="doubleclick"],iframe[src*="googlesyndication"],iframe[src*="imasdk"],iframe[src*="adsterra"],iframe[src*="popads"],iframe[src*="exoclick"]{display:none!important}';
    (document.head||document.documentElement).appendChild(st);
    sweep();
    var t=null;
    new MutationObserver(function(){if(t)return;t=setTimeout(function(){t=null;sweep()},200)})
      .observe(document.documentElement,{childList:true,subtree:true});
    setInterval(sweep,1000);
  }catch(e){}
})();""";

  /// Gentle version for download pages. It only removes frames, images and
  /// videos that are served by known ad networks. It never touches links,
  /// buttons, overlays, pop-ups, alerts or anything else, so download
  /// buttons and countdown pages keep working.
  static const adShieldLightJs = r"""
(function(){
  try{
    if(window.__dwLight)return;
    window.__dwLight=1;
    var BAD=/(doubleclick|googlesyndication|googleadservices|adnxs|adsterra|propellerads|popads|popcash|exoclick|exosrv|juicyads|trafficjunky|clickadu|hilltopads|adcash|taboola|outbrain|mgid\.com|criteo|onclickads|onclkds|profitablecpmrate|highperformanceformat|effectivegatecpm|a-ads\.com|admaven|ad-maven|monetag|richpush|bidvertiser|tsyndicate|exdynsrv)/i;
    function sweep(){
      try{
        var list=document.querySelectorAll('iframe[src],img[src],embed[src],video[src],source[src]');
        for(var i=0;i<list.length;i++){
          if(BAD.test(list[i].src||'')){try{list[i].remove()}catch(e){}}
        }
      }catch(e){}
    }
    sweep();
    var t=null;
    new MutationObserver(function(){if(t)return;t=setTimeout(function(){t=null;sweep()},400)})
      .observe(document.documentElement,{childList:true,subtree:true});
  }catch(e){}
})();""";
}
