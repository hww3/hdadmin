//
//  objectview: the view of objects in the hdadmin window
//

string view_type;
object view, box;
object vbox;

void create(string viewas)
{
  change_view(viewas);
}


void clear()
{
  view->clear();
}

void freeze()
{
  view->freeze();
}

void thaw()
{
  view->thaw();
}

object|int get_object(int i)
{
  if(view_type=="list")
    return view->get_row_data(i);
  else if(view_type=="icons")
    return view->get_icon_data(i);
}

void select_object(int i)
{
  if(view_type=="list")
    view->select_row(i);
  else if(view_type=="icons")
    view->select_icon(i);
}

array get_selected_objects()
{
  if(view_type=="list")
    return view->get_selection();
  else if(view_type=="icons")
    return view->get_selected_icons();
}

void change_view(string viewas)
{
  if(!box) box=GTK.EventBox();
  box->show();
  if(vbox) box->remove(vbox);
  if(viewas=="icons")
  {
    vbox=GTK.ScrolledWindow(0, 0);
    view=Gnome.IconList(40, 0);
    view->set_separators(" ");
    view->set_icon_width(65);
    view->set_selection_mode(GTK.SELECTION_MULTIPLE);
    view->show();
    vbox->show();
    vbox->add(view);
    box->add(vbox);
  }
  else if(viewas=="list")
  {
    if(vbox) box->remove(vbox);
    vbox=GTK.Vbox(0, 0); 
    object hbox=GTK.Hbox(0, 0);
    object vadj=GTK.Adjustment();
    object hadj=GTK.Adjustment();
    object vscroll=GTK.Vscrollbar(vadj);
    object hscroll=GTK.Hscrollbar(hadj);
    vbox->show();
    vscroll->show();
    hscroll->show();
    view=GTK.Clist(2);
    view->set_column_title(0, "Name");
    view->set_column_title(1, "Description");
    view->column_titles_show();
    view->set_selection_mode(GTK.SELECTION_SINGLE);
    view->set_column_auto_resize(0,1);
    view->set_sort_column(0);
    view->set_auto_sort(1);
    view->show();

    view->set_vadjustment(vadj);
    view->set_hadjustment(hadj);
    
    hbox->set_homogeneous(0);
    hbox->show();
    hbox->pack_end(vscroll, 0, 0, 0);
    hbox->pack_start_defaults(view);
    vbox->pack_end(hscroll, 0, 0, 0);
    vbox->pack_start_defaults(hbox);
    box->add(vbox);
  }
  view_type=viewas;
  box->set_resize_mode(GTK.RESIZE_IMMEDIATE);

}

void add_object(mapping item, object ldap, object this)
{
#ifdef DEBUG
werror("add_object: " + item->title + "\n");
#endif
  int addedrow;
  if(item->state=="locked")
  {
    if(view_type=="list")
    {
      addedrow=view->insert(0, ({item->title, (item->subtitle||"") }) );
      object px=getPixmapfromFile("icons/" + item->type + "-locked-vsm.png");
      view->set_pixtext(0, addedrow, item->title, 5, px);
    }
    else if(view_type=="icons")
      addedrow=view->insert(0, "icons/" + item->type + "-locked-sm.png", item->title);
  }
  else
  {
    if(view_type=="list")
    {
      addedrow=view->insert(0, ({item->title, (item->subtitle||"") }) );
      object px=getPixmapfromFile("icons/" + item->type + "-vsm.png");
      view->set_pixtext(addedrow, 0, item->title, 5, px);
    }
    else if(view_type=="icons")
    {
#ifdef DEBUG
werror("add_object: " + item->name + " inserting icon...");
#endif
      addedrow=view->insert(0, "icons/" + item->type + "-sm.png", item->title);
#ifdef DEBUG
werror("done.\n");
#endif
    }
  }
  object d;
#ifdef DEBUG
werror("add_object: " + item->name + " making data\n");
#endif
  d=make_object(item, ldap, this);
#ifdef DEBUG
werror("add_object: " + item->name + " setting data\n");
#endif

  if(view_type=="list")
    view->set_row_data(addedrow, d);
  else if(view_type=="icons")
    view->set_icon_data(addedrow, d);
}

object make_object(mapping item, object ldap, object this)
{
  object d;
  if(Objects[item->type])
    d=Objects[item->type](ldap, this, item->dn, item->name, 
	item->state, (item->uid||item->cn||""));
  else
    d=Objects.generic(ldap, this, item->dn, item->name, 
	item->state, (item->uid||item->cn||""));
  return d;
}


mixed signal_connect(mixed a, mixed b, mixed c)
{
  if(stringp(a) && a=="select" && view_type=="icons")
    a+="_icon";
  else if(stringp(a) && a=="select" && view_type=="list")
    a+="_row";
  if(stringp(a) && a=="unselect" && view_type=="icons")
    a+="_icon";
  else if(stringp(a) && a=="unselect" && view_type=="list")
    a+="_row";
  return view->signal_connect(a, b, c);
}

mixed signal_disconnect(int arg)
{
  return view->signal_disconnect(arg);
}



// utility functions that should probably be moved out to their own mod

mapping image_cache=([]);

object getPixmapfromFile(string filename)
{ 
  if(image_cache[filename]) return image_cache[filename];

  object p=Image.PNG.decode(Stdio.read_file(filename));
  image_cache[filename]=GDK.Pixmap(p); 
  
  return image_cache[filename];
}
