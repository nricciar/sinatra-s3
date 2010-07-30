window.onload = function ()
{
  if ($('revision_history') != null) {
    update_rev_checkboxes();
    $$('input.from').each(function (e) {
	e.onchange = update_rev_checkboxes;
    })
  }
  if ($('edit_page_form') != null) {
    $('edit_page_form').onsubmit = submit_edit_page;
  }
}
function submit_edit_page()
{
  if ($('page_comment').value == '') {
    alert('Please provide a comment describing the changes you made to the page.');
    return false;
  }
}
function update_rev_checkboxes()
{
  hide_to = false;
  rows = $$('#revision_history tr');
  rows.each(function (e) {
    f = e.getElementsBySelector('.from')[0]
    t = e.getElementsBySelector('.to')[0]
    if (f.checked == true)
      hide_to = true;

    if (hide_to == true)
      t.style.display = 'none';
    else
      t.style.display = 'inline';
  })
}
