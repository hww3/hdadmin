//
//
//  host.pike: A GTK+ based LDAP directory management tool
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

constant cvs_version="$Id: host.pike,v 1.1 2002-10-17 21:20:02 hww3 Exp $";

inherit "../util.pike";

import GTK.MenuFactory;

object ldap;

//
// what objectclasses can this module edit?
//
multiset supported_objectclasses(){return (<"iphost", "device">);}

//
// what type of object is this?
//
string type="host";

//
// can we add "new" objects of this type?
//
int writeable=1;

string dn;
string name="";
string description="";
string state;

object popup;
object popupmap;

mapping attributes,info;

object this;

int newobject;
int menuisup=0;

void create(object|void l, string|void mydn, mapping|void att, object|void th)
{  if(!l) return;

  state="";
  dn=mydn;
  if(att && att->cn)
    name=att->cn[0];
  if(att && att->description)
    description=att->description[0];
  this=th;
  ldap=l;
  if(att)
    attributes=att;
  generatePopupMenu(createPopupMenu());
  return;

}

object get_icon(string size)
{
  if(size=="small") size="-sm";
  if(size=="verysmall") size="-vsm";
  else size="";
  if(state=="locked") size="-locked" + size;
  return getPixmapfromFile("icons/host" + size + ".png");
}




void generatePopupMenu(array defs)
{
  
  [object bar,object map] = PopupMenuFactory(@defs);
  popup=bar;
  popupmap=map;
  return;
  
}

void showpopup()
{
  popup->popup(3);
  menuisup=1;
  popup->signal_connect("button_press_event",
    lambda(object m,
           GTK.Menu w,
           mapping event){
             if(menuisup){
             object a=popup->get_active();
//             if(a) a->activate();
             popup->popdown();
             menuisup=0;
             }
             return 1;
           }, 0);
  
  return;
}

array createPopupMenu()
{
  array defs;
  defs = ({
    MenuDef( "Properties...", openProperties, 0),
    MenuDef( "Delete...", openDelete, 0),
//    MenuDef( "Rename...", openRename, 0),
    MenuDef( "Move...", openMove, 0),
  });
             
  return defs;
              
}


void openMove(object r)
{
  string txt;
  txt=name;
  object moveWindow=Gnome.Dialog("Move " +  txt + "...",
    GTK.GNOME_STOCK_BUTTON_OK, GTK.GNOME_STOCK_BUTTON_CANCEL);
  mapping td=([]);
  object vbox=moveWindow->vbox();
  object t=makeTree();
  object s=GTK.ScrolledWindow(0,0);
  s->add(t->show());
  s->set_usize(275, 225);
  setupTree(t, td);
  populateTree(t, td, ldap);
  mixed selection;
  t->signal_connect(GTK.tree_select_row, lambda(object what, object
    widget, mixed selected ){ selection=selected; }, 0);
  vbox->pack_start_defaults(GTK.Label("Choose a destination for " +
    txt + ":")->show());
  vbox->pack_start_defaults(s->show());
  moveWindow->show();
  int res=moveWindow->run();
  if(res==0)  // we clicked "ok"
  {
      object newlocation=t->node_get_row_data(selection);
#ifdef DEBUG
      werror("old location: " + dn + "\n");
      werror("new location: " + newlocation->dn + "\n");
#endif
      res=doMove(newlocation);
      if(res!=0)
      {
        openError("An error occurred while trying to "
        "move an object:\n\n" +
        ldap->error_string(res));
      }
      else this->refreshView();
    moveWindow->close();
  }
  else if (res==1) moveWindow->close();
}

void openDelete()
{
  int res=doDelete();
  if(res!=0)
    openError("An error occurred while trying to "
      "delete an object: " + name + "\n\n" +
      ldap->error_string(res));
  else   this->refreshView();
  return;
}  

int doMove(object new)
{
  string newrdn=(dn/",")[0];
#ifdef DEBUG
  werror("getting ready to move " + newrdn + " to new dn: " + new->dn + 
  "\n");
#endif
  int res=ldap->modifydn(dn, newrdn, 1, newrdn+","+new->dn);
  if(!res) return ldap->error_number();
  else return 0; // non-zero if failure.
}


int doDelete()
{
  int res;
#ifdef DEBUG
  werror("deleting: " + dn + "\n");
#endif
  ldap->set_scope(2);
  ldap->set_basedn(dn);
  object r=ldap->search("objectclass=*"); 
#ifdef DEBUG
  werror(sprintf("%O\n", r->fetch()));
#endif
  array rx=r->fetch();
  if(rx->dn)
  {  
  res=ldap->delete(dn);
  if(!res) return ldap->error_number();
  else return 0; 
  }
  else werror("Unable to find object " + dn + "\n");
}




int checkChanges(string dn, mapping w)
{

  werror("entering checkChanges()\n");
  int i;
  string s;

  if(w->iphostnumber && sizeof(w->iphostnumber)==0)
  {
    openError("You must provide an IP address for this host.");
    return 1;
  }

  if(dn=="" && !w->iphostnumber)  {
    openError("You must provide an IP address for this host.");
    return 1;
  }

  if(w->dn=="") // we're adding a user, so let's make a dn up.
  {
    if(this->leftpane->node_get_text(this->current_selection, 0)=="HyperActive Directory") 
    {
	openError("No container selected.");
	return 0;
    }
    string mydn;
    object sel=this->leftpane->node_get_row_data(this->current_selection);
    mydn="cn=" + w->cn + ", "+ sel->dn;
    w->dn=mydn;
    ldap->set_basedn(w->dn);
    object rx=ldap->search("objectclass=*");
    if(rx->num_entries()!=0)
    {
      openError("You have chosen a duplicate hostname, or the\n"
	"DN is already in use. Please choose a different hostname.");
      return 0;	
    }
    w->newObject="1";
  }

  return 0; // everything's fine  
}

int doChanges(string dn, mapping whatchanged)
{
#ifdef DEBUG
  werror("doChanges for dn: " + dn + "\n");
#endif

  int res;
  mapping change=([]);

#ifdef DEBUG
  werror(sprintf("Changes: %O\n", whatchanged));
#endif

  mapping wc=copy_value(whatchanged);

  m_delete(wc, "dn");
  m_delete(wc, "propertiesWindow");
  m_delete(wc, "newObject");


  if(whatchanged->newObject) // new object
  {
#ifdef DEBUG
    werror("creating a new object for " + whatchanged->dn + "\n");
#endif

    mapping entry=([]);
    foreach(indices(wc), string attribute)
       if(!arrayp(wc[attribute]))
         entry[attribute]=({wc[attribute]});
       else entry[attribute]=wc[attribute];
    res=ldap->agressive_add(whatchanged->dn, entry);

    if(!res) return ldap->error_number();

    if(whatchanged->dn)
      dn=whatchanged->dn;
    if(whatchanged->cn)
      name=whatchanged->cn;
  }
  else  // modify entry.
  { 
#ifdef DEBUG 
    werror("changing the object: " + dn + ".\n");
#endif
 
  if(sizeof(indices(wc))>0)
  { 
    werror("we have " + sizeof(indices(wc)) + " attributes to change.\n");
    int changetype=2; // replace
    foreach(indices(wc), string attr)
    {
      if(wc[attr]=="")
        change[attr]=({changetype});
      else if(arrayp(wc[attr]))
      {
          change[attr]=({changetype});
	  foreach(wc[attr], string val)
            change[attr]+=({val});
      }
      else change[attr]=({changetype, wc[attr]});
    }
werror(sprintf("change: %O", change)); 
    res=ldap->agressive_modify(dn, change);
    if(!res) return ldap->error_number();
  }
  }
  return res;
}

void applyProperties(mapping whatchanged, object widget, mixed args)
{
  if(args==-1)
  {
    int res;
#ifdef DEBUG
    werror("applyProperties: " + sprintf("%O\n", whatchanged));
#endif
    if(checkChanges(whatchanged->dn, whatchanged))
      return;
    else res=doChanges(whatchanged->dn, whatchanged);
    if(!res)
    {
      openError("An error occurred while modifying a host: " +
	"\n\n" + ldap->error_number() + " " + 
        ldap->error_string(ldap->error_number()));
      widget->close();
      return;
    }   
    else 
    {
#ifdef DEBUG
      werror("host added/changed successfully.\n");
#endif
      if(whatchanged->dn != dn)
      {
        dn=whatchanged->dn;
        this->refreshView();
      }
#ifdef DEBUG
      werror("dn: " + dn + "\n");
#endif
  
    attributes=([]);
    loadData(); // load the object's data.
#ifdef DEBUG
      werror("post-change attributes: " + sprintf("%O\n", attributes) + "\n");
#endif
    info=attributes;
      newobject=0;
    }
  }
}

void propertiesChanged(mapping what, object widget, mixed ... args)
{
  if(widget->entry)
    what[widget->entry()->get_name()]=widget->get_text();
  if(widget->list)
  {
    what[widget->get_name()]=widget->get_contents();
    werror(widget->get_name() + " " + sprintf("%O", 
      what[widget->get_name()]));
  }
  else
    what[widget->get_name()]=widget->get_text();
  what->propertiesWindow->changed();
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

string getTextfromEntry(string|array attribute, mapping entry)
{
  if(stringp(attribute))
  {
    if(entry[attribute]) return entry[attribute][0];
    else return "";
  }
  else 
  {
    foreach(attribute, string attr)
    if(entry[attr]) 
    { 
      return entry[attr][0];
    }
  }
  return "";
}

void loadData()
{
  if(dn=="") // we have a new object.
  {
    attributes=loadDefaults();
    return;
  }
#ifdef DEBUG
werror("checking to see if we need to reload user data\n");
#endif

  if(attributes && sizeof(attributes)>0) return;
#ifdef DEBUG
werror("loading user's data from LDAP\n");
#endif
  ldap->set_scope(2);
  ldap->set_basedn(dn);
  string filter="objectclass=*";
  object res=ldap->search(filter);
  attributes=fix_entry(res->fetch());
}

mapping loadDefaults()
{
  string defaults=Stdio.read_file("defaults/" + type + ".dat");
  if(!defaults) throw("Unable to read defaults for object type " + type);
  attributes=decode_value(defaults);
#ifdef DEBUG
  werror("defaults: " + sprintf("%O", attributes) + "\n");
#endif
  return attributes;
}


string getValue(mapping att, string a)
{
   if(att && att[a] && att[a][0])
     return att[a][0];
   else return "";
}

void openProperties()
{
  mapping whatchanged=([]);

  loadData(); // load the user's data.

  info=attributes;
  werror("USER DATA: " + sprintf("%O", info) + "\n\n");
  if(dn=="") 
  {
    whatchanged=info;
    newobject=1;
  }
  string cn1= getValue(info, "cn");

  // check for the proper objectclasses
  array roc=({"device", "iphost"});

  if(dn&&dn!="") // if we aren't working on a new item, make sure the oc are correct.
  {
    for(int i=0; i< sizeof(info["objectclass"]); i++)
    {
      info["objectclass"][i]=lower_case(info["objectclass"][i]);
    }
    foreach(roc, string oc1)
    {
      if(search(info["objectclass"], oc1)==-1)  // do we have this objectclass?
      {
#ifdef DEBUG
        werror("adding objectclass " + oc1 + " for user " + dn + "\n");
#endif
        ldap->agressive_modify(dn, (["objectclass": ({0, oc1})]));    
      }
    }
  }
  object propertiesWindow;
  propertiesWindow = Gnome.PropertyBox();
  propertiesWindow->set_title("Properties of host " + cn1);
  whatchanged->propertiesWindow=propertiesWindow;
  whatchanged->dn=dn;
  object generaltab=GTK.Vbox(0, 0);
  object sourcetab=GTK.Vbox(0, 0);
  object titleline=GTK.Hbox(0, 5);
  object p=getPixmapfromFile("icons/host.png");
  object pic=GTK.Pixmap(GDK.Pixmap(p));
  titleline->pack_start_defaults(pic->show());
  titleline->pack_start_defaults(GTK.Label(cn1)->show());
  titleline->show();
  generaltab->pack_start(titleline,0,0,20);

// set up entry fields
  string tmp="";
  tmp=getTextfromEntry("description", info);
  if(newobject)
  {
    object cn=addProperty("cn", tmp, GTK.Entry());
    addItemtoPage(cn, "Hostname", generaltab);
    cn->signal_connect("changed", propertiesChanged, whatchanged);

  }

  object description=addProperty("description", tmp, GTK.Entry());

  object iphostnumber=GTKSupport.pExtraCombo()->show();
  iphostnumber->set_contents(info->iphostnumber);
  iphostnumber->set_validation_callback(validate_ip_address);
  iphostnumber->signal_connect("changed", propertiesChanged, whatchanged);
  iphostnumber->set_name("iphostnumber");
  addItemtoPage(iphostnumber, "Addresses", generaltab);
 
  object objectsource=GTK.Text();
  
  catch(objectsource->set_text(generateLDIF(info)));
  addItemtoPage(description, "Description", generaltab);

  sourcetab->pack_start_defaults(objectsource->show());
  sourcetab->show();
  // attach changed signal to all entry widgets...

  description->signal_connect("changed", propertiesChanged, whatchanged);
  propertiesWindow->signal_connect("apply", applyProperties, whatchanged);


  addPagetoProperties(generaltab, "General", propertiesWindow);
  addPagetoProperties(sourcetab, "Object Definition", propertiesWindow);

  propertiesWindow->show();
  return;
}

string|void validate_ip_address(string i)
{

  int a,b,c,d;
  if(sscanf(i,"%d.%d.%d.%d",a,b,c,d)!=4)
    return "You must provide a valid IP address.";
  if((a<0 || a>255)||(b<0 || b>255)||(c<0 || c>255)||(d<0 || d>255))
    return "Each octet in the IP address must be between 0 and 255.";
  return; 

}

/*

void showpopup()
{
  popup->popup(3);
  menuisup=1;
  popup->signal_connect("button_press_event",
    lambda(object m,
           GTK.Menu w,
           mapping event){
             if(menuisup){
	     object a=popup->get_active();
//             if(a) a->activate();
             popup->popdown();
             menuisup=0;
             }
             return 1;  
           }, 0);

  return;
}

void generatePopupMenu(array defs)
{
 
  [object bar,object map] = PopupMenuFactory(@defs);
  popup=bar;
  popupmap=map;
  return;
   
}

array createPopupMenu()
{
  array defs;
if(state=="")
  defs = ({
//    MenuDef( "New/User...", lambda(){werror("new user\n");}, 0),
    MenuDef( "Properties...", openProperties, 0),
    MenuDef( "Delete...", openDelete, 0),
    MenuDef( "Move...", openMove, 0),
    MenuDef( "Reset Password...", openPassword, 0),
    MenuDef( "Disable Account", openDisable, 0),
    MenuDef( "Add user to Group...", openAddtoGroup, 0),
    MenuDef( "<separator>", 0, 0)
  });

else if(state=="locked")
  defs = ({
    MenuDef( "Properties...", openProperties, 0 ),
    MenuDef( "Delete...", openDelete, 0 ),
    MenuDef( "Move...", openMove, 0 ),
    MenuDef( "Enable Account...", openEnable, 0 ),
    MenuDef( "<separator>", 0, 0 )
  });

 else defs = ({});

  return defs;

}

int doMove(object new)
{
  string newrdn=(dn/",")[0];
#ifdef DEBUG
  werror("getting ready to move " + newrdn + " to new dn: " + new->dn + "\n");
#endif
  int res=ldap->agressive_modifydn(dn, newrdn, 1, newrdn+","+new->dn);
  if(!res) return ldap->error_number();
  else return 0;
}

int doRename(string fn)
{
  string firstcomp=(dn/"=")[0];
  firstcomp-=" ";
  int res;
  res=ldap->agressive_modify(dn, (["gecos":({2, fn})]));
  if(!res) return ldap->error_number();
  res=ldap->agressive_modify(dn, (["cn":({2, fn})]));
  if(!res) return ldap->error_number();
  string newrdn="cn=" + fn;
  if(firstcomp=="cn")  // we have to modify the dn as well.
  {
    string newdn=({newrdn, (dn/",")[1..]})*",";
    int res=ldap->agressive_modifydn(dn, newrdn, 1);
    if(!res) return ldap->error_number();
    else
    {
      int res=resolveDependencies(dn, newdn, ldap);    
    }
  }
  name=fn; // set the object cn to our new name.
  return 0;
}

int doDelete()
{
#ifdef DEBUG
  werror("deleting: " + dn + "\n");
#endif
  ldap->set_scope(2);
  ldap->set_basedn(dn);
  object r=ldap->search("objectclass=*");
#ifdef DEBUG
  werror(sprintf("%O\n", fix_entry(r->fetch())));
#endif
  mapping rx=fix_entry(r->fetch());
  res=ldap->agressive_delete(dn);
  if(!res) return ldap->error_number();
  else return 0;
  }
  else werror("Unable to find host for " + dn + "\n");
}

void openDelete()
{
  int res=doDelete();
  if(!res)
    openError("An error occurred while trying to "
      "delete an user:\n\n User: " + name + "\n\n" +
      ldap->error_string());
  else   this->refreshView();
  return;        
}

void openMove(object r)
{
  string txt;
  txt=name;
  object moveWindow=Gnome.Dialog("Move " +  txt + "...",
    GTK.GNOME_STOCK_BUTTON_OK, GTK.GNOME_STOCK_BUTTON_CANCEL);
  mapping td=([]);
  object vbox=moveWindow->vbox();
  object t=makeTree();
  object s=GTK.ScrolledWindow(0,0);
  s->add(t->show());
  s->set_usize(275, 225);
  setupTree(t, td);
  populateTree(t, td, ldap);
  mixed selection;
  t->signal_connect(GTK.tree_select_row, lambda(object what, object
    widget, mixed selected ){ selection=selected; }, 0);
  vbox->pack_start_defaults(GTK.Label("Choose a destination for " +
    txt + ":")->show());
  vbox->pack_start_defaults(s->show());
  moveWindow->show();
  int res=moveWindow->run();
  if(res==0)  // we clicked "ok"
  {
      object newlocation=t->node_get_row_data(selection);
#ifdef DEBUG
      werror("old location: " + dn + "\n");
      werror("new location: " + newlocation->dn + "\n");
#endif
      res=doMove(newlocation);
      if(!res) 
      {
        openError("An error occurred while trying to "
   	"move an item:\n\n" +
	ldap->error_string());
      }
      else this->refreshView();
    moveWindow->close();
  }
  else if (res==1) moveWindow->close();
}

*/
