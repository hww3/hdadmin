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

constant cvs_version="$Id: hdadmin.pike,v 1.13 2002-07-19 21:43:40 hww3 Exp $";

#define HDADMIN_VERSION "0.20"

inherit "util.pike";
import GTK.MenuFactory;

#define SSL3_DEBUG 1

object ldap;
object win,status,leftpane,rightpane;
object actions;

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

void openDisconnect()
{ 
  if(isConnected==1) 
  {
    rightpane->clear();
    treedata=clearTree(leftpane, treedata);
    setupTree(leftpane, treedata);
    ldap->unbind();
    isConnected=0;
  }
}

void toggleConnect()
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
      GTK.GNOME_STOCK_BUTTON_CANCEL, GTK.GNOME_STOCK_BUTTON_OK);    
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

void openConnect()
{
  object connectWindow;
  if(isConnected==1) // we're already connected!
  {
    openError("You are already connected.");
    return;
  }
  connectWindow=Gnome.Dialog("Connect to LDAP Server",
	GTK.GNOME_STOCK_BUTTON_OK ,
	GTK.GNOME_STOCK_BUTTON_CANCEL);
  connectWindow->set_usize(300,0);
  object vbox=connectWindow->vbox();
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
        GTK.GNOME_MESSAGE_BOX_ERROR, GTK.GNOME_STOCK_BUTTON_OK);    
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
      GTK.GNOME_MESSAGE_BOX_ERROR, GTK.GNOME_STOCK_BUTTON_OK);    
      c->set_usize(275, 150);
      c->show();
      c->run_and_close();
      return 1;
    }
    populateTree(leftpane, treedata, ldap);
    isConnected=1;
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
  object aboutWindow;
  aboutWindow = Gnome.About("HyperActive Directory Administrator",
				HDADMIN_VERSION, "(c) Bill Welliver 2002",
				({"Bill Welliver", ""}),
				"Manage your LDAP directory with style.",
				"icons/spiral.png");
  aboutWindow->show();
  return;
 }

void openHostProperties(object dn)
{
  ldap->set_scope(2);
  ldap->set_basedn(dn->dn);
  string filter="objectclass=*";
  object res=ldap->search(filter);
  mapping info=res->fetch();

  // check for the proper objectclasses
  array roc=({ "top", "device", "iphost" });
  for(int i=0; i< sizeof(info["objectclass"]); i++)
  {
    info["objectclass"][i]=lower_case(info["objectclass"][i]);
  }
  foreach(roc, string oc1)
  {
    if(search(info["objectclass"], oc1)==-1)  // do we have this objectclass?
    {
#ifdef DEBUG
      werror("adding objectclass " + oc1 + " for host " + dn->dn + "\n");
#endif
      ldap->modify(dn->dn, (["objectclass": ({0, oc1})]));    
    }
  }

  object propertiesWindow;
  propertiesWindow = Gnome.PropertyBox();
  propertiesWindow->set_title("Properties of host " + info->cn[0]);

  object generaltab=GTK.Vbox(0, 0);
  generaltab->show();
  addPagetoProperties(generaltab, "General", propertiesWindow);

  object objectsource=GTK.Text();
  objectsource->set_usize(250,250);
  object sourcetab=GTK.Vbox(0, 0);
  sourcetab->pack_start_defaults(objectsource->show());
  sourcetab->show();
  addPagetoProperties(sourcetab, "Object Definition", propertiesWindow);

  objectsource->set_text(generateLDIF(info));

  object vbox=propertiesWindow->vbox();
  vbox->show();
//      "So you want to see information about the Host "+ dn->dn + "?\n\n"
//      + message,  
//      GTK.GNOME_MESSAGE_BOX_INFO, Gnome.StockButtonOk);
  propertiesWindow->show();
  return;
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
   
  }

  return defs;
}

mixed newActionsPopup()
{
  werror("got newactionspopup\n");
  array defs=({});

  if(isConnected && treeselection) defs+=
  ({
    MenuDef( "New User...", openNew, "user" ),
    MenuDef( "New Group...", openAbout, 0 ),
    MenuDef( "New Host...", openAbout, 0 ), 
    MenuDef( "New Mail Alias...", openAbout, 0 ),
    MenuDef( "<separator>", openDisconnect, 0 )
    });
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
    object d=rightpane->make_object((["name": "New " + type, "type": type,
        "dn": "" ]), ldap, this_object());
    d->openProperties();
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
  object icon=GTK.Pixmap(getPixmapfromFile("icons/connect.png"))->show();
  object toolbar=GTK.Toolbar(GTK.ORIENTATION_HORIZONTAL, GTK.TOOLBAR_ICONS);
  toolbar->append_item("Connect/Disconnect", "Connect/Disconnect", "", icon,
    toggleConnect, 0);
  toolbar->append_space();
  toolbar->append_item("Actions", "Actions", "", GTK.Label("Actions")->show(), openActions, 0);
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
  rightpane=.Objects.objectview(preferences->display->viewas);
  scroller1->add(leftpane);
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
  if(t=="HyperActive Directory") return;

#ifdef DEBUG
  werror("getting values for " + t + "\n");
#endif
  object data=widget->node_get_row_data(selected);
  ldap->set_scope(1);
  ldap->set_basedn(data->dn);

  string filter="!(|(objectclass=organizationalunit)(objectclass=organization))";
  object res=ldap->search(filter, 0, ({"dn", "objectclass", "cn",
	"userpassword", "uid", "sn", "givenname"}));  
  array n=({});
  array ent=({});
  for(int i=0; i<res->num_entries(); i++)
  {
    mapping m=res->fetch();
    string nom="";
    if(m["sn"] && m["givenname"])
      nom=(m["sn"][0] + m["givenname"][0]);
    n+=({nom});
    ent+=({res->fetch()});
    res->next();
  }
  sort(n, ent);
  rightpane->freeze();
  foreach(reverse(ent), mapping entry)
  {
    string item="_unknown_";
    string state="";

    array oc=entry["objectclass"];
    string dn=entry["dn"][0];
#ifdef DEBUG
    werror("checking type of entry for " + item + "\n");
    werror(sprintf("%O", oc));
#endif
    type=getTypeofObject(oc);
    state=getStateofObject(type, entry);
 
    catch(item=entry["cn"][0]);
    if(type=="user")
    {
    if(entry && !entry["sn"])
	entry["sn"]=({""});
    if(entry && !entry->givenname)
    {
       if(entry->gn)
	 entry->givenname=entry->gn;
       else
         entry->givenname=({""});
    }
 
      if(preferences->display->cn=="lastnamefirst")
        item=entry["sn"][0] + ", " + entry["givenname"][0];
      else if(preferences->display->cn=="firstnamefirst")
        item=entry["givenname"][0] + " " + entry["sn"][0];
    }
    if(item && type[0..3]=="user")
      rightpane->add_object(([ "name": item, "type": type, "state": state, 
	"dn": entry["dn"][0], "uid": entry["uid"][0] ]), ldap, this_object());
    else
      rightpane->add_object((["name": item, "type": type, 
	"dn": entry["dn"][0] ]), ldap, this_object());
#ifdef DEBUG
werror("added item.\n");
#endif
  }
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

