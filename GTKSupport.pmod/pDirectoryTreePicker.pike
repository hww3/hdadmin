
object hbox;
object label;
object choosebutton;

string path="";
string nicepath="";

private object hb2,vscroll,vadj; // for the scrolled list

object pathwindow;

private mapping callbacks=([]);

int allow_duplicates=0;

inherit GTK.Hbox;
inherit "../util.pike";

object ldap;

private function check_callback;

void create(object _ldap)
{
  ldap=_ldap;
  label=GTK.Label("Directory")->show();
  choosebutton=GTK.Button(" Choose ")->show();
  choosebutton->signal_connect(GTK.button_press_event, private_openchoose, 0);
  ::create(0,0);
  ::pack_start(label, 0,0,3);
  ::pack_start(choosebutton, 0,0,3);
//  ::show();
}

string get_path()
{
   return path;
}

string get_nicepath()
{
   return nicepath;
}

object show()
{
  ::show();
  return this_object();
}

void set_path(string dn)
{
  path=dn;
  set_nicepath();
}

private void set_nicepath()
{
   array np=path/",";
   for(int n=0; n<sizeof(np); n++)
   {
     np[n]=String.capitalize(String.trim_whites((np[n]/"=")[1]));
   }     
  nicepath=np*"/";
  label->set_text(nicepath);
}

private void private_openchoose()
{

  object chooseWindow=Gnome.Dialog("Choose Directory...",
    GTK.GNOME_STOCK_BUTTON_OK, GTK.GNOME_STOCK_BUTTON_CANCEL);
  mapping td=([]);
  object vbox=chooseWindow->vbox();
  object t=makeTree();
  object s=GTK.ScrolledWindow(0,0);
  s->add(t->show());
  s->set_usize(275, 225);
  setupTree(t, td);
  populateTree(t, td, ldap);
  mixed selection;
  t->signal_connect(GTK.tree_select_row, lambda(object what, object
    widget, mixed selected ){ selection=selected; }, 0);
  vbox->pack_start_defaults(GTK.Label("Choose a directory:")->show());
  vbox->pack_start_defaults(s->show());
  chooseWindow->show();
  int res=chooseWindow->run();
  if(res==0)  // we clicked "ok"
  {
      object newlocation=t->node_get_row_data(selection);
#ifdef DEBUG
      werror("old location: " + dn + "\n");
      werror("new location: " + newlocation->dn + "\n");
#endif
      set_path(newlocation->dn);
      chooseWindow->close();
  }
  else if (res==1) chooseWindow->close();

  return;

}

mixed get_contents()
{
  return "";
}

void set_contents(string c)
{
  return;
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

void set_allow_duplicates(int yesno)
{
  allow_duplicates=yesno;
}

void set_validation_callback(function cb)
{
  if(functionp(cb))
    check_callback=cb;
}

private void private_unselect_row()
{
}

private void private_select_row()
{
}

private void private_add_row()
{
}

private void private_delete_row()
{
}
