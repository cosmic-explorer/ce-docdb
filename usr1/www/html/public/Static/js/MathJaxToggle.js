/***********************************************************
 *
 * The $ object used to manupulate DOM is NOT FROM JQUERY
 *
 * it is from PROTOTYPE.JS 
 *
 ***********************************************************/


function Toggle_Renderer() {
  var renderer_name = "CommonHTML";
  if (MathJax.Hub.config.menuSettings.renderer != 'PlainSource') {
     renderer_name = "PlainSource";
  }
  MathJax.Hub.setRenderer(renderer_name);
  MathJax.Hub.Config({render:renderer_name});
}

function RefreshMath() {
  MathJax.Hub.Reprocess();
}

function ShowMathJaxButton() {
   if (!$("MathJax_Toggle") && $("MathJax-Element-1")) {
     $("MathJaxInsert").insert(
       "<p style='margin-left:2em;'>\n"+
       "<a href='Javascript:helppopupwindow(\"/cgi-bin/private/DocDB/DocDBHelp?term=whatismathjax\");'><img src='https://www.mathjax.org/badge/logo_60x12.gif' /></a>: \n" +
       "<a href='#' onclick='Toggle_Renderer();' id='MathJax_Toggle'></a>\n"+
       "</p>\n"
       );
   }

   var mjx_lnk =$("MathJax_Toggle");
   if (mjx_lnk) {
     if (MathJax.Hub.config.menuSettings.renderer == 'PlainSource') {
         mjx_lnk.update("Enable");
     } else {
         mjx_lnk.update("Disable");
     } 
   }
}


document.addEventListener('DOMContentLoaded', (event) => {
    MathJax.Hub.Config({  
         tex2jax: {
             inlineMath: [['\\(','\\)']],
             processEscapes: true
         },
         CommonHTML: { linebreaks: { automatic: true } },
         "HTML-CSS": { linebreaks: { automatic: true } },
         SVG: { linebreaks: { automatic: true } }, 
         PlainSource: {   ".MathJax_PlainSource_Display": {
             "text-align": "center",
             margin: ".75em 0px",
             "white-space": "pre", 
             display: "block"
      } }
    });
    MathJax.Hub.Register.MessageHook("End Math", ShowMathJaxButton);
    MathJax.Hub.Register.MessageHook("Renderer Selected", RefreshMath);
})

