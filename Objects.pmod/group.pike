//
//
//  group.pike: A GTK+ based LDAP directory management tool
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

constant cvs_version="$Id: group.pike,v 1.3 2003-01-02 23:01:16 hww3 Exp $";

inherit "../util.pike";

import GTK.MenuFactory;

object ldap;

multiset supported_objectclasses(){return (<"posixgroup", "group">);}

string type="group";
int writeable=1;

string dn;
string name="";
string description="";
string state;

object popup;
object popupmap;

mapping attributes, info;

object this;

int menuisup=0;
int newgroup=0;  


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
  return getPixmapfromFile("icons/user" + size + ".png");
}

string getNextGIDNumber()
{
  int mingid=1001;
  int maxgid=29999;

  int proposed_gid;

  while(1){

  // generate a random uidnumber.
  proposed_gid=random(maxgid-mingid) + mingid;

  werror("proposed_gid: " + proposed_gid + "\n");

  // now check to see if it's in use.
  array g=getGidfromGidnumber((string)proposed_gid, ldap);
  if(sizeof(g)==0) break; 
  }

  return (string)proposed_gid;
}

int checkGroupChanges(string dn, mapping w)
{

  werror("entering checkGroupchanges()\n");
  int i;
  string s;

  if((dn=="" && !w->cn) || (w->cn && w->cn==""))  // we have to have a groupname
  {
    openError("Groupname cannot be empty.");
    return 1;
  }
  if(dn=="" && (!w->gidnumber || w->gidnumber=="")) // we dont have a gidnumber so lets find one.
  {
    w->gidnumber=getNextGIDNumber();
  }

  if(w->gidnumber && w->gidnumber!="" && !isaNumber(w->gidnumber))
  {
    openError("Numeric Group ID must be a number.");
    return 1;
  }
  if(w->gidnumber && w->gidnumber!="") // is the uid in use by some other group?
  {
    array g=getGidfromGidnumber(w->gidnumber, ldap);
    if(sizeof(g)>0)
    {
      string myuname=lower_case(name);
      foreach(g, string gid)
      {
        if(lower_case(gid)!=myuname)
        {
          object c=Gnome.MessageBox("Numeric Group ID " + w->gidnumber + 
            " is already in use by " + gid + "."
            "\nDo you really want to have duplicate Group IDs?", 
		Gnome.MessageBoxInfo,
                Gnome.StockButtonCancel, Gnome.StockButtonOk);    
    
          c->set_usize(375, 150);
          c->show();
          int returnvalue=c->run_and_close();
          if(returnvalue==1)
            return 1; // no, we don't want duplicate ids
          else return 0; // we're ok with the duplicate ids
          
        }
      }
    }
  }

  if(w->dn=="") // we're adding a group, so let's make a dn up.
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
      openError("You have chosen a duplicate groupid, or the\n"
	"DN is already in use. Please choose a different userid.");
      return 0;	
    }
    w->newObject="1";
  }

  return 0; // everything's fine  
}

int doGroupChanges(string dn, mapping whatchanged)
{
#ifdef DEBUG
  werror("doGroupChanges for dn: " + dn + "\n");
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


  if(whatchanged->newObject) // new group account
  {
#ifdef DEBUG
    werror("creating a new group account for " + whatchanged->dn + "\n");
#endif
    mapping entry=([]);
    foreach(indices(wc), string attribute)
       if(!arrayp(wc[attribute]))
         entry[attribute]=({wc[attribute]});
       else entry[attribute]=wc[attribute];
#ifdef DEBUG
werror("adding entry: " + sprintf("%O", entry) + "\n");
#endif
    res=ldap->agressive_add(whatchanged->dn, entry);

    if(!res) return ldap->error_number();

    if(whatchanged->dn)
      dn=whatchanged->dn;
    if(whatchanged->cn)
      name=whatchanged->cn;
  }
  else
  { 
#ifdef DEBUG 
    werror("checking the group: " + dn + ".\n");
#endif
    ldap->set_basedn(whatchanged->dn);
    object rx=ldap->search("objectclass=*");
    if(rx->num_entries()==0) return 32; // no such group
    name=fix_entry(rx->fetch())["cn"][0];
    werror("GNAME: " + name + "\n");
    if(whatchanged->cn) // we need to change the groupname.
    { 
      // first, check to see that the groupname isn't already taken.
      ldap->set_basedn(ldap->BASEDN);
      string filter="(&(cn=" + whatchanged->cn +
        ")(objectclass=posixgroup))";
#ifdef DEBUG
      werror("filter: " + filter + "\n");
#endif
      rx=ldap->search(filter, 0, ({"cn"}));
      if(rx->num_entries()) 
      {
        whatchanged->propertiesWindow->changed();
        openError("Group " + whatchanged->cn + " already exists.\nPlease choose another.");
        return 0;
      }
      // next, we need to update groups
      array newdn=(whatchanged->dn/",");
      newdn[0]="cn=" + whatchanged->cn;
      res=resolveDependencies(whatchanged->dn, newdn*",", ldap);

      // then change the dn.
      res=ldap->agressive_modifydn(whatchanged->dn, "cn=" + whatchanged->cn, 1);
      if(!res) return ldap->error_number();
      newdn=(whatchanged->dn/",");
      newdn[0]="cn=" + whatchanged->cn;
      whatchanged->dn=newdn*",";
      if(whatchanged->cn)    
        name=whatchanged->cn;    
    }
  }
 
  if(sizeof(indices(wc))>0)
  { 
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
#ifdef DEBUG
   werror("changing attributes in main record...");
#endif

#ifdef DEBUG
werror(sprintf("CHANGES: %O\n", change));
#endif

    res=ldap->agressive_modify(dn, change);
    if(!res) return ldap->error_number();
#ifdef DEBUG
   werror("done.\n");
#endif
  }

#ifdef DEBUG
  werror(sprintf("%O\n", change));
#endif
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
    if(checkGroupChanges(whatchanged->dn, whatchanged))
      return;
    else res=doGroupChanges(whatchanged->dn, whatchanged);
    if(!res)
    {
      openError("An error occurred while modifying a group: " +
	"\n\n" + ldap->error_number() + " " + 
        ldap->error_string(ldap->error_number()));
      widget->close();
      return;
    }   
    else 
    {
#ifdef DEBUG
      werror("group added/changed successfully.\n");
#endif
      if(whatchanged->dn != dn)
      {
        dn=whatchanged->dn;
        this->refreshView();
      }
      if(whatchanged->cn != name) name=whatchanged->cn;
#ifdef DEBUG
      werror("dn: " + dn + "\n");
#endif
  
    attributes=([]);
    loadData(); // load the group's data.
    info=attributes;
      newgroup=0;
    }
  }
}

void propertiesChanged(mapping what, object widget, mixed ... args)
{
  if(widget->entry)
    what[widget->entry()->get_name()]=widget->get_text();
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

int addUsertoGroup(string usercn, string userdn)
{
  if(usercn=="" || dn=="" || userdn=="")  return 0;
  if(!dn || !userdn || !userdn)  return 0;
  int res=ldap->agressive_modify(dn, (["memberuid": ({ 0, usercn}),
			"uniquemember": ({ 0, userdn})
    ]));
  return res;
}

int removeUserfromGroup(string usercn, string userdn)
{
  werror("removing " + usercn + " dn: " + userdn + " from " + dn + "\n");
  int res=ldap->agressive_modify(dn, (["memberuid": ({ 1, usercn}),
			"uniquemember": ({ 1, userdn})
    ]));
  return res;
}

void loadData()
{
  if(dn=="") // we have a new object.
  {
    attributes=loadDefaults();
    return;
  }
#ifdef DEBUG
werror("checking to see if we need to reload group data\n");
#endif

  if(attributes && sizeof(attributes)>0) return;
#ifdef DEBUG
werror("loading group's data from LDAP\n");
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

  loadData(); // load the group's data.

  info=attributes;
  werror("GROUP DATA: " + sprintf("%O", info) + "\n\n");
  if(dn=="") 
  {
    whatchanged=info;
    newgroup=1;
  }
  string cn1= getValue(info, "cn");

  // check for the proper objectclasses
  array roc=({"posixgroup", "groupofuniquenames"});

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
        werror("adding objectclass " + oc1 + " for group " + dn + "\n");
#endif
        ldap->agressive_modify(dn, (["objectclass": ({0, oc1})]));    
      }
    }
  }
  object propertiesWindow;
  propertiesWindow = Gnome.PropertyBox();
  propertiesWindow->set_title("Properties of group " + cn1);
  whatchanged->propertiesWindow=propertiesWindow;
  whatchanged->dn=dn;
  object objectsource=GTK.Text();
  object generaltab=GTK.Vbox(0, 0);
  object sourcetab=GTK.Vbox(0, 0);
  object memberstab=GTK.Vbox(0, 0);
  object titleline=GTK.Hbox(0, 5);
  object p=getPixmapfromFile("icons/group.png");
  object pic=GTK.Pixmap(GDK.Pixmap(p));
  titleline->pack_start_defaults(pic->show());
  titleline->pack_start_defaults(GTK.Label(cn1)->show());
  titleline->show();
  generaltab->pack_start(titleline,0,0,20);

// set up entry fields
  string tmp="";

  tmp=getTextfromEntry("cn", info);
  object cn=addProperty("cn", tmp, GTK.Entry());
  tmp=getTextfromEntry("gidnumber", info);
  object gidnumber=addProperty("gidnumber", tmp, GTK.Entry());

  tmp=getTextfromEntry("description", info);
  object description=addProperty("description", tmp, GTK.Entry());

// set up the group membership pane.
  array ag=getMembersforGroup(0, ldap);
  object allmembers=newMemberList(ag);
  object groupmemberships=GTK.Clist(2);
  object adj1=GTK.Adjustment();  
  object scr1=GTK.Vscrollbar(adj1)->show();
  object hb3=GTK.Hbox(0,0)->show();
  groupmemberships->set_vadjustment(adj1);
  groupmemberships->set_usize(150,200);
  groupmemberships->set_sort_column(1);
  groupmemberships->set_sort_type(GTK.SORT_ASCENDING);
  groupmemberships->set_auto_sort(1);
  groupmemberships->show();
  hb3->pack_start_defaults(groupmemberships);
  hb3->pack_start_defaults(scr1);

  description->set_usize(200,0);
  objectsource->set_usize(250,250);
  
  array gm=({});
  if(dn!="")
    gm=getMembersforGroup(info->dn[0], ldap);  
  foreach(gm, array ginfo)
  { 
    int row=groupmemberships->append(({"group",ginfo[1]+ " (" + ginfo[0]+")"}));
    row=groupmemberships->set_row_data(row, userentry(ginfo[0], ginfo[2], ginfo[1]));
  }

  groupmemberships->sort();

  catch(objectsource->set_text(generateLDIF(info)));

  addItemtoPage(cn, "Groupname", generaltab);
  addItemtoPage(description, "Description", generaltab);
  addItemtoPage(gidnumber, "Group ID Number", generaltab);

  object hb2=GTK.Hbox(0,0);
  object vb1=GTK.Vbox(0,0);
  object vb2=GTK.Vbox(0,0);
  object vb3=GTK.Vbox(0,0);

  object addbutton=GTK.Button(" < ");
  object removebutton=GTK.Button(" > ");
  addbutton->signal_connect("clicked", lambda(object what, object widget,
mixed ... args){
if(newgroup)
{
  openError("Click Apply to add the group\n"
    " before adding members.");
  return;
}

array selection=allmembers->allmembers->get_selection();
foreach(selection, int row)
  {
    object d=allmembers->allmembers->get_row_data(row);
#ifdef DEBUG
    werror("adding group membership: " + d->name + " to group " + dn +"\n");
#endif
    int res=addUsertoGroup(d->name, d->dn);
    if(!res) openError("An error occurred while adding a group membership:\n\n" + ldap->error_string());
    else
    {
      groupmemberships->freeze();
      int row=groupmemberships->append(({"user",d->description + " (" +
d->name + ")"}));
      groupmemberships->sort();
      groupmemberships->thaw();
      row=groupmemberships->set_row_data(row, groupentry(d->name, d->dn, d->description));
    }
  }
}
,groupmemberships);
  removebutton->signal_connect("clicked", lambda(object what, object widget,
mixed ... args){
if(newgroup)
{
  openError("Click Apply to add the group\n"
    " before removing members.");
  return;
}
array selection=groupmemberships->get_selection();
foreach(selection, int row)
  {
    object d=groupmemberships->get_row_data(row);
#ifdef DEBUG
    werror("removing group member: " + d->name + " from group " + 
	dn  + "\n");
#endif
    int res=removeUserfromGroup(d->name, d->dn);
    if(!res) openError("An error occurred while removing a group membership:\n\n" + ldap->error_string());
    else
    {
      int row=groupmemberships->remove(row);
    }
  }
}
,groupmemberships);
  
  vb2->pack_start(addbutton->show(),0,15,15);
  vb2->pack_start(removebutton->show(),0,15,15);
  vb1->pack_start_defaults(GTK.Label("Current Members")->show());
  vb3->pack_start_defaults(GTK.Label("Available Users")->show());
  vb1->pack_start_defaults(hb3->show());
  vb3->pack_start_defaults(allmembers->hb4->show());
  groupmemberships->show();
  hb2->pack_start(vb1->show(),0,15,15);
  hb2->pack_start(vb2->show(),0,15,15);
  hb2->pack_start(vb3->show(),0,15,15);
  memberstab->pack_start(hb2->show(),0,15,15);
  sourcetab->pack_start_defaults(objectsource->show());
  sourcetab->show();
  // attach changed signal to all entry widgets...

  cn->signal_connect("changed", propertiesChanged, whatchanged);
  gidnumber->signal_connect("changed", propertiesChanged, whatchanged);
  description->signal_connect("changed", propertiesChanged, whatchanged);
  propertiesWindow->signal_connect("apply", applyProperties, whatchanged);


  addPagetoProperties(generaltab, "General", propertiesWindow);
  addPagetoProperties(memberstab, "Members", propertiesWindow);
  addPagetoProperties(sourcetab, "Object Definition", propertiesWindow);

  propertiesWindow->show();
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
//    MenuDef( "New/Group...", lambda(){werror("new user\n");}, 0),
    MenuDef( "Properties...", openProperties, 0),
    MenuDef( "Delete...", openDelete, 0),
    MenuDef( "Move...", openMove, 0),
    MenuDef( "Reset Password...", openPassword, 0),
    MenuDef( "Disable Group", openDisable, 0),
    MenuDef( "Add user(s) to Group...", openAddtoGroup, 0),
    MenuDef( "<separator>", 0, 0)
  });

else if(state=="locked")
  defs = ({
    MenuDef( "Properties...", openProperties, 0 ),
    MenuDef( "Delete...", openDelete, 0 ),
    MenuDef( "Move...", openMove, 0 ),
    MenuDef( "Enable Group...", openEnable, 0 ),
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

int doEnable(string password)
{
  int res;
  mapping change=(["userpassword":({2, password })
		]);

  res=ldap->agressive_modify(dn, change);

#ifdef DEBUG
  werror(sprintf("%O\n", change));
#endif
  if(!res) return ldap->error_number();
  else return 0;
}

int doPassword(string password)
{
  int res;
  mapping change=(["userpassword":({2, password })
		]);

  res=ldap->agressive_modify(dn, change);

#ifdef DEBUG
  werror(sprintf("%O\n", change));
#endif
  if(!res) return ldap->error_number();
  else return 0;
}

int doDisable()
{
  int res=ldap->agressive_modify(dn, (["userpassword":({2, "{crypt}*LK*"})]));
  if(!res) return ldap->error_number();
  return 0;
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
  werror(sprintf("%O\n", fix_entry(r->fetch())));
#endif
  mapping rx=fix_entry(r->fetch());
  if(rx->gidnumber)
  {
    string gidnumber=rx["gidnumber"][0];
  array members=getMembersofPrimaryGroup(gidnumber, ldap);
  if(sizeof(members)>0)
  {
    openError("You are trying to delete\n"
	"the primary group of the following users:\n\n"
	+ (members*"\n") + "\nPlease change these users before continuing.");
    return 0;
  }
  res=ldap->agressive_delete(dn);
  if(!res) return ldap->error_number();
  else return 0;
  }
  else werror("Unable to find group for " + dn + "\n");
}

void openDisable()
{
  int res=doDisable();
  if(res) 
  {
    openError("An error occurred while trying to "
      "disable a group:\n\n Group: " + name + "\n\n" +
      ldap->error_string());
    return;        
  }
  else this->refreshView();
  return;
}

void openDelete()
{
  int res=doDelete();
  if(res)
    openError("An error occurred while trying to "
      "delete an group:\n\n Group: " + name + "\n\n" +
      ldap->error_string());
  else   this->refreshView();
  return;        
}

void openAddtoGroup()
{
  string groupdn;
  object addWindow=Gnome.Dialog("Add a user to group " + name + "...",
  GTK.GNOME_STOCK_BUTTON_OK, GTK.GNOME_STOCK_BUTTON_CANCEL);
  object vbox=addWindow->vbox();
  array ag=getMembersforGroup(0, ldap);

  object allmembers=newMemberList(ag);
  vbox->pack_start(GTK.Label("Choose select user(s) to add to this group:"
	)->show(), 0,0,0);
  vbox->pack_start(allmembers->hb4->show(),0,0,0);
  addWindow->show();
  int res=addWindow->run();
  if(res==1);
  else 
  {
    array sr=allmembers->allmembers->get_selection();
#ifdef DEBUG
    werror(sprintf("selection: %O\n", sr));
#endif
    if(sizeof(sr)==0);
    else 
    {
      foreach(sr, int row)
      {
        object selectedgroup=allmembers->allmembers->get_row_data(row);
#ifdef DEBUG
        werror("adding group for " + selectedgroup->cn + "\n");
#endif
        int res=addUsertoGroup(selectedgroup->name, selectedgroup->dn);
        if(!res) 
        {
          openError("An error occurred while trying to "
   	  "add the following user to a group:\n\n User: " + selectedgroup->cn + "\n\n" +
  	ldap->error_string());
//          refreshView();
          return;        
        }
      }
    }
  }
  if(res !=-1)
    addWindow->close();
}

void openEnable()
{
  string txt;
  txt=name;
  if(state!="locked")
  {
    openError("You may only enable disabled groups.");
    return;
  }
  object enableWindow=Gnome.Dialog("Enable " +  txt + "...",
    GTK.GNOME_STOCK_BUTTON_OK, GTK.GNOME_STOCK_BUTTON_CANCEL);
  object vbox=enableWindow->vbox();
  object password=GTK.Entry();
  object password2=GTK.Entry();
  password->set_visibility(0);
  password2->set_visibility(0);
  addItemtoPage(password, "Password", vbox);
  addItemtoPage(password2, "Retype Password", vbox);
  enableWindow->set_default(0);
  enableWindow->editable_enters(password2);
  vbox->show();
  int wres=enableWindow->run();
  while(wres==0)
  {
    if(wres==0){
      int res;
      if(password->get_text() != password2->get_text()) 
      {
        openError("Your passwords don't match.");
        wres=enableWindow->run();
        continue;
      }
      else if(password->get_text() == "")
      {
        openError("Your password is too short.");
        wres=enableWindow->run();
        continue;
      }
      else 
        res=doEnable(password->get_text());
      if(res) 
      {
          openError("An error occurred while trying to "
   	    "enable a group:\n\n Group: " + name + "\n\n" +
            ldap->error_string());
          return;        
      }
      else 
      {
        this->refreshView();
        break;
      }
    }

  }
  if(wres!=-1)
  {
    enableWindow->close();
  }
}

void openPassword(object r)
{
  string txt;
  txt=name;
  object passwordWindow=Gnome.Dialog("Reset password for " +  txt + "...",
    GTK.GNOME_STOCK_BUTTON_OK, GTK.GNOME_STOCK_BUTTON_CANCEL);
  object vbox=passwordWindow->vbox();
  mixed selection;
  object password=GTK.Entry();
  object password2=GTK.Entry();
  password->set_visibility(0);
  password2->set_visibility(0);
  addItemtoPage(password, "Password", vbox);
  addItemtoPage(password2, "Retype Password", vbox);
  password->grab_focus();
  passwordWindow->editable_enters(password2);
  vbox->show();
  passwordWindow->show();
  int res=passwordWindow->run();
  while(res==0)
  {
    if(res==0){
      int res;
      if(password->get_text() != password2->get_text()) 
      {
        openError("Your passwords don't match.");
        res=passwordWindow->run();
        continue;
      }
      else if(password->get_text() == "")
      {
        openError("Your password is too short.");
        res=passwordWindow->run();
        continue;
      }
      else 
        res=doPassword(password->get_text());
      if(res!=0) 
      {
          openError("An error occurred while trying to "
   	    "change a group's password:\n\n Group: " + name + "\n\n" +
            ldap->error_string());
          return;        
      }
      else break;
    }
  }
  if(res!=-1)
  {
    passwordWindow->close();
    this->refreshView();
  }
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

