
object list;
object add;
object delete;
object input;
object hbox;
object vbox;
private object hb2,vscroll,vadj; // for the scrolled list

private mapping callbacks=([]);

inherit GTK.Vbox;


private function check_callback;

void create()
{
  vadj=GTK.Adjustment();
  vscroll=GTK.Vscrollbar(vadj)->show();

  list=GTK.Clist(1)->show();  
  list->set_vadjustment(vadj);
  list->signal_connect(GTK.select_row, private_select_row, 0);
  list->signal_connect(GTK.unselect_row, private_unselect_row, 0);

  hb2=GTK.Hbox(0,0)->show();
  hb2->pack_start(list, 1,1,0);

  hb2->pack_start(vscroll, 0,0,0);

  delete=GTK.Button(" Delete ")->show();
  delete->set_sensitive(0);
  delete->signal_connect(GTK.button_press_event, private_delete_row, 0);

  add=GTK.Button("  Add  ")->show();
  add->signal_connect(GTK.button_press_event, private_add_row, 0);

  input=GTK.Entry()->show();

  hbox=GTK.Hbox(0,0);
  hbox->pack_start(input, 0,0,1);
  hbox->pack_end(delete, 0,0,1);
  hbox->pack_end(add, 0,0,1);
  hbox->show();

  ::create(0,0);
  ::pack_start(hb2, 0,0,0);
  ::pack_end(hbox, 0,0,0);
  ::show();
}

object show()
{
  ::show();
  return this_object();
}

array get_contents()
{
  array c=({});
  int e=list->get_rows();

  for(int i=0; i<e; i++)
    c+=({ list->get_text(i,0) });
  return c;
}

void set_contents(array c)
{
  if(!c || sizeof(c)==0)
    return 0;
  foreach(c, string row)
    list->append( ({row}) );
}

void get_selection()
{

}

void set_selection(array rows)
{
  return;
}

int signal_connect(string signal, function callback, mixed|void callback_arg)
{
  if(signal=="changed")
  {
    if(!callbacks->changed) callbacks->changed=({});    
    callbacks->changed +=({({callback, callback_arg})});
  }
  else
      ::signal_connect(signal, callback, callback_arg);
}

void set_validation_callback(function cb)
{
  if(functionp(cb))
    check_callback=cb;
}

private void private_unselect_row()
{
  delete->set_sensitive(0);
}

private void private_select_row()
{
  delete->set_sensitive(1);
}

private void private_add_row()
{
   string res;
   string i=input->get_text();

   if(check_callback && functionp(check_callback))
      res=call_function(check_callback, i);

   if(res || !i) // validation of input failed. display error.
   {
      GTKSupport.Alert(res);  
   }
   else
   {
      list->append(({i}));
      if(callbacks->changed)
        foreach(callbacks->changed, array cb)
          cb[0](cb[1], this_object(), "+" + i);
   }

   return;
}

private void private_delete_row()
{
  array r=list->get_selection();
  if(r && sizeof(r) > 0)
    foreach(r, int row)
    {
      string d=list->get_text(row,0);
      list->remove(row);
      if(callbacks->changed)
        foreach(callbacks->changed, array cb)
          cb[0](cb[1], this_object(), "-" + d);
      
    }
}
