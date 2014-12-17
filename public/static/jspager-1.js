
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

function displayInfo() {
  var sel = getElementsByClass('subpage',null,'div');
  if (document.getElementById('singleFull').checked) {
    for (var i=0; i<sel.length; i++) {
      sel[i].style.display = 'block';
      sel[i].style.height="auto";
    }
  } else {
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
  if (document.getElementById('singleFull').checked) { return; }
  var sel = getElementsByClass('subpage',null,'div');
  qno = qno + qnoDirection;
  if (setPage != 0) { qno = setPage-1; }
  if (qnoDirection < 0) { if (qno < 0) { qno = 0; } }
                   else { if (qno > sel.length-1) { qno = sel.length-1; } }
  sel[oqno].style.display = 'none';
  sel[qno].style.display = 'block';
  oqno = qno;
  document.getElementById('pageDisplay').innerHTML
    = '<b>Pg.'+(qno+1)+'/'+sel.length+'</b>';
}

function gotoPageDisplay() {
  var sel = getElementsByClass('subpage',null,'div');
  var str = '';
  for (var i=0; i<sel.length; i++) {
    str += '<input type="radio" name="pgno"';
    str += ' onclick="qno='+i+';showQuestion(0,'+(i+1)+')">'+(i+1)+' ';
  }
  document.getElementById('gotoPage').innerHTML = str;
}

window.onload = function() {
  showQuestion(0,0);
  gotoPageDisplay();
}

function validate() {
  alert('Validation / Grading to be added.');
  return false;
}
