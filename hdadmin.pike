#!/usr/local/bin/pike -M.

//
//
//  hdadmin.pike: A GTK+ based LDAP directory management tool
//
//  Copyright 2002 by Bill Welliver <hww3@riverweb.com>
//
//
//  This program is free software; you can redistribute it and/or
//  modify it under the terms of the GNU General Public License
//  as published by the Free Software Foundation; either version 2
//  of the License, or (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program; if not, write to the Free Software
//  Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307,
//  USA.
//
//

constant cvs_version="$Id: hdadmin.pike,v 1.23 2003-06-17 19:17:46 hww3 Exp $";

#define HDADMIN_VERSION "0.2.5"

inherit "util.pike";
import GTK.MenuFactory;

#define SSL3_DEBUG 1

object ldap;
object win,status,leftpane,rightpane;
object actions;
object connectButton;
mixed connectButtonsignal;
object searchButton;
mixed searchButtonsignal;

mapping objectclass_map=([]);
mapping preferences=([]);

string ROOTDN;

int isConnected=0;
object treeselection;
mapping treedata=([]);
int main(int argc, array argv) {

 if(file_stat( getenv("HOME")+"/.pgtkrc" ))
    GTK.parse_rc( cpp(Stdio.read_bytes(getenv("HOME")+"/.pgtkrc")) );
write("Starting HyperActive Directory Administrator " + HDADMIN_VERSION +  "...\n");

// let's load the preferences.

preferences=loadPreferences();
// start up the ui...

Gnome.init("HDAdmin", HDADMIN_VERSION , argv);
win=Gnome.App("HDAdmin", "HyperActive Directory");
win->set_usize(600,400);
setupMenus();
setupToolbar();
setupContent();
setupTree(leftpane, treedata);
leftpane->signal_connect(GTK.tree_select_row, showIcons, 0);
leftpane->signal_connect(GTK.tree_select_row, updateSelection, 1);
leftpane->signal_connect(GTK.tree_unselect_row, updateSelection, 0);
leftpane->signal_connect(GTK.button_press_event, clickDirectoryTree, 0);
setupStatus();
win->signal_connect(GTK.delete_event, appQuit, 0);
win->show();

return -1;
}

void appQuit()

{
  _exit(0);
}

void setConnected(int c)
{
  if(c)
  {
    connectButton->signal_block(connectButtonsignal);
    connectButton->set_active(1);
    connectButton->signal_unblock(connectButtonsignal);
    searchButton->signal_block(searchButtonsignal);
    searchButton->set_sensitive(1);
    searchButton->signal_unblock(searchButtonsignal);
    isConnected=1;
  }
  else
  {
    connectButton->signal_block(connectButtonsignal);
    connectButton->set_active(0);
    connectButton->signal_unblock(connectButtonsignal);
    searchButton->signal_block(searchButtonsignal);
    searchButton->set_sensitive(0);
    searchButton->signal_unblock(searchButtonsignal);
    isConnected=0;
  }
}

void openDisconnect()
{ 
  if(isConnected==1) 
  {
    rightpane->clear();
    treedata=clearTree(leftpane, treedata);
    setupTree(leftpane, treedata);
    ldap->unbind();
    setConnected(0);
  }
}

void toggleConnect()
{
  if(isConnected==1) openDisconnect();
  else openConnect();
}

void toggleSearch()
{
  if(isConnected==1) openDisconnect();
  else openConnect();
}

void doLDIFSave(object what, object widget, mixed ... args)
{ 
  string outputfile=what->get_filename();
  if(file_stat(outputfile))
//    write("file " + outputfile + " exists...\n");
  {
    object c=Gnome.MessageBox("File exists...", 
      Gnome.MessageBoxError,
      Gnome.StockButtonOk, Gnome.StockButtonCancel);
/*
"The file you chose already
exists.\n" +
	"Overwrite " + outputfile + "?",
*/
    
    c->set_usize(275, 150);
    c->show();
    int returnvalue=c->run_and_close();
    if(returnvalue==1)
      return;
  }

//  write("writing objects to " + outputfile + "\n");
  string output="";

  array selected=rightpane->get_selected_objects();

  foreach(selected, int sel) 
  {
    object data=rightpane->get_object(sel);
    ldap->set_scope(2);
    ldap->set_basedn(data->dn);
    string filter="objectclass=*";
    object res=ldap->search(filter);
    mapping info=res->fetch();
    output+=generateLDIF(info);
    output+="\n";
  }
//  write("output: \n\n" + output + "\n"); 
    Stdio.write_file(outputfile, output);
  closeSaveWindow(what, widget, args);
}

void closeSaveWindow(object what, object widget, mixed ... args)
{
  what->hide();
  what->destroy();
}

void openSaveWindow()
{
  array selected=rightpane->get_selected_objects();
  if(sizeof(selected)<1)
  {
    openError("You must select an object to save.");
    return;
  }
  string txt;
  
  string selection=sizeof(selected) + " objects";
  object window=GTK.FileSelection("Save " + selection + " as LDIF...");

  window->complete("*.ldif");
  window->show();
  object ok=window->ok_button();
  object cancel=window->cancel_button();
//write(sprintf("%O", indices(cancel)));

  cancel->signal_connect("clicked", closeSaveWindow, window);
  ok->signal_connect("clicked", doLDIFSave, window);

}

object addProperty(string name, string value, object o)
{
  if(value && o->entry)
    o->entry()->set_text(value);
  else if(value && o->set_text)
    o->set_text(value);
  if(name && o->entry)
    o->entry()->set_name(name);
  else
    o->set_name(name);
  return o;
}

void openConnect()
{
  setConnected(0);
  object connectWindow;
  if(isConnected==1) // we're already connected!
  {
    openError("You are already connected.");
    return;
  }
  connectWindow=Gnome.Dialog("Connect to LDAP Server",
	Gnome.StockButtonOk ,
	Gnome.StockButtonCancel);
  connectWindow->set_usize(350,0);
  object pane=connectWindow->vbox();
  object vbox=GTK.Vbox(0,0)->show();
  object hb=GTK.Hbox(0,0)->show(); 
  
  hb->pack_start_defaults(GTK.Pixmap(
     getPixmapfromFile("icons/directory_server.png"),
     getBitmapfromFile("icons/directory_server_mask.png"))->show());
  hb->pack_end_defaults(vbox);
  pane->pack_start_defaults(hb);
  object host=Gnome.Entry("LDAPHOST");
  object basedn=Gnome.Entry("BASEDN");
  object username=Gnome.Entry("ROOTDN");
  object password=GTK.Entry();
  password->set_visibility(0);
  host->load_history();
  username->load_history();
  if(ROOTDN)
    username->gtk_entry()->set_text(ROOTDN);
  else if(getenv("LOGNAME"))
    username->gtk_entry()->set_text(getenv("LOGNAME"));
  host->set_usize(200,0);
  basedn->set_usize(200,0);
  username->set_usize(200,0);
  password->set_usize(200,0);
  connectWindow->editable_enters(password);  
  // load default server uri(s) into host box.
  mapping conf=([]);
  if(file_stat( "/etc/ldap.conf" ))
    conf=.readconf.readconf("/etc/ldap.conf");
  if(file_stat( getenv("HOME")+"/.ldaprc" ))
    conf+=.readconf.readconf( getenv("HOME")+"/.ldaprc" );
  if(conf) 
  {
    array serv=.readconf.get_conn_info(conf);
    string bdn=.readconf.get_base_dn(conf);
    if(sizeof(serv)>0)
      {
        host->entry()->set_text(serv[0]);
        foreach(serv, string s) 
        {
          host->prepend_history(0, s);
        }
      }
    if(bdn)
        basedn->gtk_entry()->set_text(bdn);
  }

  addItemtoPage(host, "Server", vbox);
  addItemtoPage(basedn, "Base DN", vbox);
  addItemtoPage(username, "Username", vbox);
  addItemtoPage(password, "Password", vbox);
  
  vbox->show();
  connectWindow->set_default(0);
  connectWindow->show();
  password->grab_focus();
  password->set_position(0);
//  password->activate();

  string h,u,p;
  int res,keeptrying;
  do
  {
    res=connectWindow->run();

    if(res==0)  // user pressed ok 
    {
      host->save_history();
      username->save_history();
      h=host->entry()->get_text();
      u=username->entry()->get_text();
      p=password->get_text();
    }
    if(res==-1) break;
    else if(res==1) break;
    else ROOTDN=u;
  }
  while(doConnect(h, u, p, basedn->entry()->get_text()));
  if(connectWindow) 
    connectWindow->close();
  
  return;

}

object makeEntry(object widget, string desc)
{
  object hbox=GTK.Hbox(0, 0);
  hbox->pack_start_defaults(GTK.Label(desc)->show());
  hbox->pack_start_defaults(widget->show());
  return hbox;
}

int doConnect(string host, string username, string password, string basedn)
{
  if(isConnected==0)
  {
    object context=SSL.context();
    ldap=LDAPConn(host, context);
    if(sizeof(username/"=")==1)  // we need to find the dn for uid
    {
      string filter1="(&(objectclass=account)(uid=" +
       username + "))";
      ldap->set_scope(2);
      ldap->BASEDN=basedn;
      ldap->set_basedn(ldap->BASEDN);
      object rslts=ldap->search(filter1);
      if(rslts->num_entries()!=1) // didn't find the person
      {
        object c=Gnome.MessageBox("Login incorrect (check your userid).",
	  Gnome.MessageBoxError, Gnome.StockButtonOk, 
	  Gnome.StockButtonCancel);    
        c->set_usize(275, 150);
        c->show();
        c->run_and_close();
        return 1;
      }
      username=rslts->get_dn();
#ifdef DEBUG
      werror("connecting as " + username + "\n");
#endif
    }
    int r=ldap->bind(username, password, 3);
    if(r!=1) {
      object c=Gnome.MessageBox(ldap->error_string(), 
	Gnome.MessageBoxError,
        Gnome.StockButtonOk);    
      c->set_usize(275, 150);
      c->show();
      c->run_and_close();
      return 1;
    }

    ldap->LDAPHOST=host;
    ldap->USER=username;
    ldap->USERPASS=password;

    populateTree(leftpane, treedata, ldap);
    setConnected(1);
    return 0;
  }
  return 1;
}

void openAbout()
{
  object aboutWindow;
  aboutWindow = Gnome.About("HyperActive Directory Administrator",
				HDADMIN_VERSION, "(c) Bill Welliver 2002",
				({"Bill Welliver", ""}),
				"Manage your LDAP directory with style.",
				"icons/spiral.png");
  aboutWindow->show();
  return;
 }

void openFixCN()
{
  array dns=getDNfromSelection();
  foreach(dns, object o)
  {
    if(o->fixcn)
      o->fixcn(([]));
  }
}

void openPreferences()
{

  object propertiesWindow;
  propertiesWindow = Gnome.PropertyBox();
  propertiesWindow->set_title("Preferences");

  object displaytab=GTK.Vbox(0, 0);
  object usertab=GTK.Vbox(0, 0);

  object dvo=GTK.OptionMenu();
  object dcn=GTK.OptionMenu();

  dvo->set_menu(GTK.Menu()->append(GTK.MenuItem("List")->show())
	->append(GTK.MenuItem("Icons")->show())->show());

  dcn->set_menu(GTK.Menu()->append(GTK.MenuItem("First Name First")->show())
	->append(GTK.MenuItem("Last Name First")->show())->show());

  object defaultview=addProperty("defaultview", "", dvo);
  addItemtoPage(defaultview, "Default View", displaytab);

  object displaycn=addProperty("displaycn", "", dcn);
  addItemtoPage(displaycn, "Display Names as", displaytab);

  object sshpath=addProperty("sshpath", "/usr/bin/ssh", GTK.Entry());
  addItemtoPage(sshpath, "SSH/RSH Path", usertab);

  addPagetoProperties(displaytab, "Display", propertiesWindow);
  addPagetoProperties(usertab, "User Objects", propertiesWindow);

  propertiesWindow->show();
}

object generatePopupMenu(array defs)
{
 
  [object bar,object map] = PopupMenuFactory(@defs);
  
  return bar;
   
}

array createPopupMenu(string type)
{
  array defs=({});

  if(type=="tree")
  {
    defs+=({MenuDef( "New Organizational Unit...", openNewOU, 0 )});
    defs+=({MenuDef( "Delete Organizational Unit...", openDeleteOU, 0 )});
   
  }

  return defs;
}

mixed newActionsPopup()
{
  array defs=({});

  if(isConnected && treeselection)
  {
    foreach(
      indices(Objects), string n)
        if(Objects[n]()->writeable)
        defs+=({MenuDef("New " + upper_case(n[0..0]) + n[1..] + "...", openNew, n)});

   defs+=
  ({    MenuDef( "<separator>", openDisconnect, 0 ) });
  }
  if(isConnected) defs+=
  ({
    MenuDef( "Disconnect", openDisconnect, 0 )
  });
  else defs+=({
    MenuDef( "Connect...", openConnect, 0)
    });

 [object menu, object map]=PopupMenuFactory( @defs);
  return menu;
}

void openNew(string type)
{
    object d=rightpane->make_object(type, ldap, this_object());
    d->openProperties();
}

void propertiesChanged(mapping what, object widget, mixed ... args)
{
  if(widget->entry)
    what[widget->entry()->get_name()]=widget->get_text();
  else
    what[widget->get_name()]=widget->get_text();
  what->propertiesWindow->changed();
}

void openDeleteOU()
{
  string loc="";
  object data=leftpane->node_get_row_data(treeselection);
  string tmp=replace(data->dn, ({"\\,"}), ({"``"}));
  array comp=tmp/",";
  array comp1=({});
  foreach(comp, string c)
    comp1+=({String.trim_whites((c/"=")[1])});
  loc=replace(comp1*"/", ({"``"}), ({"\\,"}));

    object c=Gnome.MessageBox("Delete " + loc + "?", 
      Gnome.MessageBoxError,
      Gnome.StockButtonOk, Gnome.StockButtonCancel);
    
    c->set_usize(275, 150);
    c->show();
    int returnvalue=c->run_and_close();
    if(returnvalue==1)
      return;
    else
       doDeleteOU(data->dn);

    return;
}

void openNewOU()
{
  mapping whatchanged=([]);

  object propertiesWindow;
  propertiesWindow = Gnome.PropertyBox();
  propertiesWindow->set_title("Create New Organizational Unit");
  whatchanged->propertiesWindow=propertiesWindow;
  object generaltab=GTK.Vbox(0, 0);

  string loc="";

  object data=leftpane->node_get_row_data(treeselection);
  string tmp=replace(data->dn, ({"\\,"}), ({"``"}));
  array comp=tmp/",";
  array comp1=({});
  foreach(comp, string c)
    comp1+=({String.trim_whites((c/"=")[1])});
  loc=replace(comp1*"/", ({"``"}), ({"\\,"}));
  werror("loc: " + loc + "\n");
  object par=GTK.Label(loc)->show();
  object ou=addProperty("ou", "", GTK.Entry());
  object description=addProperty("description", "", GTK.Entry());

  generaltab->show();

  ou->signal_connect("changed", propertiesChanged, whatchanged);
  description->signal_connect("changed", propertiesChanged, whatchanged);

  addItemtoPage(par, "Create in", generaltab);
  addItemtoPage(ou, "Organizational Unit", generaltab);
  addItemtoPage(description, "Description", generaltab);
  addPagetoProperties(generaltab, "General", propertiesWindow);
  propertiesWindow->signal_connect("apply", addNewOU, (["ou": ou, 
    "description": description]));
  propertiesWindow->show();

}

void doDeleteOU(string oudn)
{
    int res;
#ifdef DEBUG
    werror("deleting ou: " + oudn + "\n\n");
#endif
    res=ldap->delete(oudn);
    if(!res)
    {
       openError("An LDAP error occurred:\n" + ldap->error_string());
       return;
    }
    else
    {
     treedata=clearTree(leftpane, treedata);
     setupTree(leftpane, treedata);
     populateTree(leftpane, treedata, ldap);

    }

}

void addNewOU(mixed whatchanged, object widget, mixed args)
{
  if(args==-1)
  {
    int res;
#ifdef DEBUG
    werror("addNewOU\n");
#endif
    if(whatchanged->ou->get_text()=="")
    {
      openError("You must provide a value for the Organizational Unit.");
      return;
    }
    if(whatchanged->description->get_text()=="")
    {
      openError("You must provide a value for the Description.");
      return;
    }
    // we're at the end and the input is valid.

    object data=leftpane->node_get_row_data(treeselection);
    string mydn="ou=" + 
       (replace(whatchanged->ou->get_text(), ",", "\\,")) + ", " + 
       data->dn;
#ifdef DEBUG
    werror("my new dn: " + mydn + "\n\n");
#endif
    res=ldap->add(mydn, (["objectclass": ({"top", "organizationalunit"}),
"ou": ({whatchanged->ou->get_text()}), 
"description": ({whatchanged->description->get_text()})]));
    if(!res)
    {
       openError("An LDAP error occurred:\n" + ldap->error_string());
       return;
    }
    else
    {
     treedata=clearTree(leftpane, treedata);
     setupTree(leftpane, treedata);
     populateTree(leftpane, treedata, ldap);

    }
  }
}

void refreshView()
{
  if(current_selection)
    showIcons(0, leftpane, current_selection);
}

void openActions()
{
 if(menuisup==0 && popupmenu) popupmenu=0;
  if(!popupmenu) popupmenu=newActionsPopup();
    popupmenu->popup(1);
    menuisup=1;
    popupmenu->signal_connect("button_press_event", lambda(object m,
							GTK.Menu w,
							mapping event){
				popupmenu->popdown();
                                menuisup=0;
				return 1;
				}, 0);

}

void setupToolbar()
{
  object conicon=GTK.Pixmap(getPixmapfromFile("icons/connect.png"),
      getBitmapfromFile("icons/connect_mask.png"))->show();
  object searchicon=GTK.Pixmap(getPixmapfromFile("icons/search.png"),
      getBitmapfromFile("icons/search_mask.png"))->show();
  object 
actionicon=GTK.Pixmap(getPixmapfromFile("icons/actions.png"), 
getBitmapfromFile("icons/actions_mask.png"))->show();

  connectButton=GTK.ToggleButton()->add(conicon)->show();
  connectButtonsignal=connectButton->signal_connect("clicked", 
    toggleConnect, 0);
  connectButton->set_mode(0);

  
  searchButton=GTK.Button()->add(searchicon)
    ->set_relief(GTK.RELIEF_NONE)->show();
  searchButtonsignal=searchButton->signal_connect("clicked", 
    toggleSearch, 0);
  searchButton->set_sensitive(0);

  object toolbar=GTK.Toolbar(GTK.ORIENTATION_HORIZONTAL, GTK.TOOLBAR_ICONS);
  toolbar->append_widget(connectButton, "Connect to a directory server", 
     "Private");
  toolbar->append_space();
  toolbar->append_item("Actions", "Commonly used actions", "", actionicon,
    openActions, 0);
  toolbar->append_widget(searchButton, "Search the directory tree", 
     "Private");

//  toolbar->set_style(GTK.TOOLBAR_BOTH);
  toolbar->show();
  win->set_toolbar(toolbar);
}

void doAction(object what, object widget, mixed ... args)
{
  
}

void setupMenus() 
{
  mapping sc = GTK.Util.parse_shortcut_file( "simple_menu_shortcuts" );

  array defs = ({
    GTK.MenuFactory.MenuDef( "File/Connect...", openConnect, 0 ),
    GTK.MenuFactory.MenuDef( "File/Disconnect...", openDisconnect, 0 ),
    GTK.MenuFactory.MenuDef( "File/Save as LDIF...", openSaveWindow, 0 ),
    GTK.MenuFactory.MenuDef( "File/<separator>", 0, 0 ),
    GTK.MenuFactory.MenuDef( "File/Quit...", appQuit, 0 ),
    GTK.MenuFactory.MenuDef( "Edit/Copy DN", openAbout, 0 ),
    GTK.MenuFactory.MenuDef( "Edit/Select All...", doSelectAllIcons, 0 ),
    GTK.MenuFactory.MenuDef( "Edit/Preferences...", openPreferences, 0 ),
    GTK.MenuFactory.MenuDef( "View/<radio:viewas>Icons", 
viewAsIcons, 0 
),
    GTK.MenuFactory.MenuDef( "View/<radio:viewas>List", 
viewAsList, 0 ),
    GTK.MenuFactory.MenuDef( "View/<separator>...", 0, 0 ),
    GTK.MenuFactory.MenuDef( "View/Refresh...", refreshView, 0 ),
    GTK.MenuFactory.MenuDef( "Help/About...", openAbout, 0 ),
  });

  foreach(defs, object o) 
    if(sc[o->menu_path])
      o->assign_shortcut( sc[o->menu_path] );

  GTK.MenuFactory.set_menubar_modify_callback( lambda(mapping m) {
          GTK.Util.save_shortcut_file( "simple_menu_shortcuts", m );
     });  
  [object bar,object map] = GTK.MenuFactory.MenuFactory(@defs);
  GTK.MenuFactory.set_menubar_modify_callback( 0 );  
  
  win->add_accel_group( map );
  win->set_menus(bar);
   

}
  
int cont;

void viewAsList()
{
  rightpane->change_view("list");
  refreshView();
}

void viewAsIcons()
{
  rightpane->change_view("icons");
  refreshView();
}

void doSelectAllIcons()
{
  rightpane->select_all_objects();
  return;
}

void setupStatus()
{
  status=GTK.Statusbar();
  status->set_usize(0,19);
  cont=status->get_context_id("Main Application");
  status->push(cont, "HyperActive Directory Administrator Ready.");
  win->set_statusbar(status);

}

void pushStatus(string stat)
{  
//  status->pop(cont);
  status->push(cont, stat);

}

void popStatus()
{  
  status->pop(cont);
//  status->push(cont, stat);

}

void setupContent()
{
  object pane=GTK.Hpaned();
  object scroller1=GTK.ScrolledWindow(0,0);
  leftpane=makeTree();
werror("creating an objectview.\n");
  rightpane=.Objects.objectview(preferences->display->viewas);
  scroller1->add(leftpane);
werror("done.\n");
  pane->set_position(200);
  pane->add1(scroller1);
  pane->add2(rightpane->box);
  scroller1->show();
  leftpane->show();
  win->set_contents(pane);
}

mapping clearTree(object t, mapping td)
{
  object c;
#ifdef DEBUG
werror(sprintf("%O\n", indices(td->root)));  
#endif
    c=td->root->child();
  while(c && c!=td->root) 
  {
    t->remove_node(c);
    c=td->root->child();
  }  
  t->remove_node(td->root);
  td=([]);
  return td;
}

//   td=treedata, r=row to map, t=ctree object, parent=parent node
void mapitem(mapping td, array r, object t, object parent, string myroot)
{
  // remove any spaces in the leading piece of component.
  array newrow=({});
  foreach(r[0], string ent)
  {
  array c=ent/"=";
  c[0]-=" ";
  c[1]=((c[1]/" ")-({""}))*" ";
  newrow+=({c*"="});
  }

  godown(t, td, ({newrow, r[1]}), td->root);
}

void godown(object tree, mapping treedata, array row, object parent)
{
  string component=row[0][0];
  // does the piece exist in the tree?
  if(treedata[component]);  
  else 
  {
    string cn=(component/"=")[1];
    treedata[component]=([]);
    treedata[component]["nodename"]=component;
    treedata[component]["node"]=tree->insert_node(parent, 0, ({cn}), 0, 0);
    tree->node_set_row_data(treedata[component]["node"], 
        treeentry(cn, row[1]));
  }
  if(sizeof(row[0])>1)
  godown(tree, treedata[component], ({row[0][1..], row[1]}), 
     treedata[component]["node"]);
  else return;

}

array climbtree(object t, object r, array a, mapping t2)
{
#ifdef DEBUG
   werror("climbtree.\n");
#endif
  if(r->parent() && (r->parent()!=t2->root))
  {
    a+=({t->node_get_row_data(r)->name});
    a=climbtree(t,r->parent(),a, t2);
  }
  return a;
}
object current_selection;
mixed clickevent;

void updateSelection(mixed what, object widget, mixed selected)
{
if(what==1)
  treeselection=selected;
else
  treeselection=0;
}

void showIcons(mixed what, object widget, mixed selected)
{
  string type;

  rightpane->signal_disconnect(clickevent);
  current_selection=selected;
  string t=widget->node_get_text(selected, 0);
  rightpane->clear();
  rightpane->freeze();
  if(t=="HyperActive Directory") return;

#ifdef DEBUG
  werror("getting values for " + t + "\n");
#endif
  object data=widget->node_get_row_data(selected);
  ldap->set_scope(1);
  ldap->set_basedn(data->dn);

  string filter="!(|(objectclass=organizationalunit)(objectclass=organization))";
  object res=ldap->search(filter);
  for(int i=0; i<res->num_entries(); i++)
  {
    mapping entry=res->fetch();
    rightpane->add_object(ldap, this_object(), entry);
    res->next();
  }
#ifdef DEBUG
werror("added item.\n");
#endif
rightpane->thaw();
array dn2=({});
array dnc=(data->dn/",");
foreach(dnc, string d)
  dn2+=({(d/"=")[1]});
string ndn=reverse(dn2)*"/";
rightpane->thaw();
pushStatus("Viewing " + res->num_entries() + " items in " + ndn +
".\n");
clickevent=rightpane->signal_connect(GTK.button_press_event, clickIconList, 0);
rightpane->signal_connect("select", selectIcon, 0);
rightpane->signal_connect("unselect", unselectIcon, 0);

}

GTK.Menu popupmenu;
int menuisup=0;
int clickIconList(object what, object widget, mixed selected)
{ 

  object data;
  array n;

  if(menuisup==0 && popupmenu) popupmenu=0;
#ifdef DEBUG
  werror(sprintf("%O ", selected->button));
  werror(sprintf("%O\n", selected->type));
#endif
  if( selected->button == 3 ) 
  {
    array n=rightpane->get_selected_objects();
    object data;

    if(sizeof(n)>=1) 
    {
      data=rightpane->get_object(n[0]);
    }
  
    if(data && data->showpopup) 
    {
      data->showpopup(3);
      return 1;
    }
  }

  else if(selected->type=="2button_press" && selected->button==1)
  {
    n=rightpane->get_selected_objects();
    if(sizeof(n)>=1) 
    {
      data=rightpane->get_object(n[0]);
      data->openProperties();
    }
    return 0;
  }


  return 0;

}

int clickDirectoryTree(object what, object widget, mixed selected)
{ 
 if(menuisup==0 && popupmenu) popupmenu=0;

             if( selected->button == 3 && treeselection) {
object data=leftpane->node_get_row_data(treeselection);
  if(!popupmenu)
  popupmenu = generatePopupMenu(createPopupMenu("tree"));
	popupmenu->popup(3);
        menuisup=1;
        popupmenu->signal_connect("button_press_event", lambda(object m,
							GTK.Menu w,
							mapping event){
				popupmenu->popdown();
                                menuisup=0;
				return 1;
				}, leftpane);
        return 1;

  }
  return 0;

}

array getDNfromSelection()
{
  array dns=({});
  array selection=rightpane->get_selected_objects();
  foreach(selection, int icon)
  {
    object d=rightpane->get_object(icon);
    dns+=({d});
  }
  return dns;
}

int selectIcon(int what, object widget, mixed selected)
{ 
  array dns=getDNfromSelection();
  if(sizeof(dns)>1) 
    pushStatus("Selected " + sizeof(dns) + " items.");
  else
    pushStatus("Selected " + dns[0]->dn + ".");
}


int unselectIcon(int what, object widget, mixed selected)
{ 
  popStatus();
}

