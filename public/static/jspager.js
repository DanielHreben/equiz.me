function $_(IDS) { return document.getElementById(IDS); }

function getElementsByClass(searchClass,node,tag) {
 var classElements = new Array();
 if (node == null) node = document;
 if (tag == null) tag = '*';
 var els = node.getElementsByTagName(tag);
 var elsLen = els.length;
 var pattern = new RegExp("(^|\\s)"+searchClass+"(\\s|$)");
 for (i = 0, j = 0; i < elsLen; i++) {
   if (pattern.test(els[i].className) ) {
     classElements[j] = els[i];
     j++;
   }
 }
 return classElements;
}

function displayAllInfo(el) {
 var sel = getElementsByClass('subpage',null,'div');
 if ($(el).attr('checked')) {
     $('.singleFull').attr('checked', 'checked');
   for (var i=0; i<sel.length; i++) {
     sel[i].style.display = 'block';
     sel[i].style.height="auto";
   }
 } else {
     $('.singleFull').removeAttr('checked');
   for (var i=0; i<sel.length; i++) {
     sel[i].style.display = 'none';
     sel[i].style.height="50%";
   }
   showQuestion(0,0);
 }
}
var qno = 0;
var oqno = 0;

function showQuestion(qnoDirection,setPage) {
 var sel = getElementsByClass('subpage',null,'div');
 qno = qno + qnoDirection;
 if (setPage != 0) { qno = setPage-1; }
 if (qnoDirection < 0) { if (qno < 0) { qno = 0; } }
                  else { if (qno > sel.length-1) { qno = sel.length-1; } }
 if (sel[oqno]) {
     sel[oqno].style.display = 'none';
 }
 if (sel[qno]) {
     sel[qno].style.display = 'block';
 }
 oqno = qno;
 $('.selectPage').each(function(el) {
     this.selectedIndex = qno;
     //alert(this);
     //alert($(this).get(0).selectedIndex);
     //$(this).attr('selectedIndex', 4);
     //console.log($(this).attr('selectedIndex'));
 });
}
function displayPage(info) {
 $('.singleFull').attr('checked', false);
 displayAllInfo();
 showQuestion(0,info);
}
window.onload = function() {
 showQuestion(0,0);
}
function validate() {
 alert('Validation / Grading to be added.');
 return false;
}
