//
//  objectview: the view of objects in the hdadmin window
//

inherit "../util.pike";

string view_type;
object view, box;
object vbox;
int display_ou=0;
mapping objectclass_map=([]);

void create(string viewas)
{
  change_view(viewas);
  foreach(indices(Objects), string o)
  {
    if(o=="objectview") continue; // we don't want to checkourselves and get into a loop!
//    werror("checking in " + o + "\n");
    multiset ocs=(<>);
    if(Objects[o] && Objects[o]()->supported_objectclasses)
      ocs=Objects[o]()->supported_objectclasses();
    foreach(indices(ocs), string oc)
      objectclass_map[oc]=o;
  }
//  werror("objectclass_map: " + sprintf("%O", objectclass_map) + "\n");
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
  view->sort();
  view->thaw();
}

void set_display_ou(int b)
{
  display_ou=b;
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
    if(display_ou)
      view=GTK.Clist(3);
    else
      view=GTK.Clist(2);
    view->set_column_title(0, "Name");
    view->set_column_title(1, "Description");
    if(display_ou)
      view->set_column_title(2, "Location");
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

void add_object(object ldap, object this, mapping entry)
{
  int addedrow;
  object d;
  object px;
  d=make_object(entry, ldap, this);
  if(view_type=="list")
  {
      if(display_ou)
        addedrow=view->insert(0, ({"", d->description,
          make_nicepath(((d->dn/",")[1..])*",") }) );
      else
        addedrow=view->insert(0, ({"", d->description }) );
      px=d->get_icon("verysmall");
      view->set_pixtext(0, addedrow, d->name, 5, px);
  }
  else if(view_type=="icons")
  {
     addedrow=view->insert(0, "icons/" + d->type + "-sm.png", d->name);
  }

  if(view_type=="list")
    view->set_row_data(addedrow, d);
  else if(view_type=="icons")
    view->set_icon_data(addedrow, d);
}

object make_object(mapping|string entry, object ldap, object this)
{
  if(stringp(entry))
  {
    object d;
    if(Objects[entry])
      d=Objects[entry](ldap, "", ([]), this);
    return d;
  }
  else 
  {
    entry=fix_entry(entry);

    string type=getTypeofObject(entry->objectclass);
    object d;
    if(Objects[type])
      d=Objects[type](ldap, entry->dn[0], entry, this);
    else
      d=Objects.generic(ldap, entry->dn[0], entry, this);
    return d;
  }
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

string getTypeofObject(array oc)
{
  string type="generic";
  foreach(oc, string o)
  {
    o=lower_case(o);
    if(o=="top") continue;
    if(objectclass_map[o])
    {
      type=objectclass_map[o];
      break;
    }
  }

 return type;

}
