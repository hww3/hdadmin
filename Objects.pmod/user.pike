//
//
//  user.pike: A GTK+ based LDAP directory management tool
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

constant cvs_version="$Id: user.pike,v 1.1 2002-04-29 23:34:16 hww3 Exp $";

inherit "../util.pike";

import GTK.MenuFactory;

object ldap;

string type="user";

string dn;
string cn;
string state;
string uid;

object popup;
object popupmap;

mapping data;

object this;

int menuisup=0;
int newuser=0;  

void create(object l, object th, string n, string c, string t, string|void u)
{
    state=t;
    dn=n;
    this=th;
    cn=c;
    if(u)
      uid=u;
  ldap=l;
  generatePopupMenu(createPopupMenu());
  return;
}

string getNextUIDNumber()
{
  int minuid=1001;
  int maxuid=29999;

  int proposed_uid;

  while(1){

  // generate a random uidnumber.
  proposed_uid=random(maxuid-minuid) + minuid;

  werror("proposed_uid: " + proposed_uid + "\n");

  // now check to see if it's in use.
  array g=getUidfromUidnumber((string)proposed_uid, ldap);
  if(sizeof(g)==0) break; 
  }

  return (string)proposed_uid;
}

int checkUserChanges(string dn, mapping w)
{

  werror("entering checkUserchanges()\n");
  int i;
  string s;

  if((dn=="" && !w->uid) || (w->uid && w->uid==""))  // we have to have a username
  {
    openError("Username cannot be empty.");
    return 1;
  }
  if((dn=="" && !w->homedirectory) || (w->homedirectory && w->homedirectory==""))  // we have to have a home directory
  {
    openError("Home directory cannot be empty.");
    return 1;
  }
  if(w->useautohome && (!w->autohomedirectory
|| sizeof(w->autohomedirectory/":")!=2))  // we have to have a valid autohome directory
  {
    openError("AutoMount Home Directory location\nmust be of the following form:\n"
      "host:/path/to/home");
    return 1;
  }
  if(dn=="" && !w->uidnumber) // we dont have a uidnumber so lets find one.
  {
    w->uidnumber=getNextUIDNumber();
  }

  if(w->uidnumber && !isaNumber(w->uidnumber))
  {
    openError("Numeric User ID must be a number.");
    return 1;
  }
  if(w->uidnumber) // is the uid in use by someone else?
  {
    array g=getUidfromUidnumber(w->uidnumber, ldap);
    if(sizeof(g)>0)
    {
      string myuname=lower_case(getUidfromDN(dn, ldap));
      foreach(g, string uid)
      {
        if(lower_case(uid)!=myuname)
        {
          object c=Gnome.MessageBox("Numeric User ID " + w->uidnumber + 
            " is already in use by " + uid + "."
            "\nDo you really want to have duplicate User IDs?", 
            GTK.GNOME_STOCK_BUTTON_CANCEL, GTK.GNOME_STOCK_BUTTON_OK);    
    
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
  if(dn=="" && !(w->givenname && w->sn))
  {
    openError("You must provide first and last names for this user.");
    return 1;

  }
  if(dn=="" && (!w->gidnumber))
  {
    openError("You must select a primary group for this user.");
    return 1;
  }
  if(w->gidnumber && getGidfromName(w->gidnumber, ldap)==-1)
  {
    openError("Primary Group must already exist.");
    return 1;
  }
  if(w->shadowmin && !isaNumber(w->shadowmin))
  {
    openError("Minimum Password Lifetime must be a number.");
    return 1;
  }
  if(w->shadowmax && !isaNumber(w->shadowmax))
  {
    openError("Maximum Password Lifetime must be a number.");
    return 1;
  }
  if(w->shadowwarning && !isaNumber(w->shadowwarning))
  {
    openError("Password Lifetime Warning must be a number.");
    return 1;
  }
  if(w->shadowinactive && !isaNumber(w->shadowinactive))
  {
    openError("Inactivity period must be an integer.");
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
    mydn="uid=" + w->uid + ", "+ sel->dn;
    w->dn=mydn;
    ldap->set_basedn(w->dn);
    object rx=ldap->search("objectclass=*");
    if(rx->num_entries()!=0)
    {
      openError("You have chosen a duplicate userid, or the\n"
	"DN is already in use. Please choose a different userid.");
      return 0;	
    }
    w->newObject="1";
  }

  return 0; // everything's fine  
}

int doUserChanges(string dn, mapping whatchanged)
{
#ifdef DEBUG
  werror("doUserChanges for dn: " + dn + "\n");
#endif

  int res;
  mapping change=([]);

#ifdef DEBUG
  werror(sprintf("Changes: %O\n", whatchanged));
#endif

  mapping wc=copy_value(whatchanged);

  m_delete(wc, "dn");
  m_delete(wc, "useautohome");
  m_delete(wc, "autohomedirectory");
  m_delete(wc, "propertiesWindow");
  m_delete(wc, "newObject");


  if(whatchanged->newObject) // new user account
  {
#ifdef DEBUG
    werror("creating a new account for " + whatchanged->dn + "\n");
#endif

    mapping entry=([]);
    foreach(indices(wc), string attribute)
       if(!arrayp(wc[attribute]))
         entry[attribute]=({wc[attribute]});
       else entry[attribute]=wc[attribute];
    entry["cn"]=({makecn(wc)});
    entry["gecos"]=({makecn(wc)});
#ifdef DEBUG
werror("adding entry: " + sprintf("%O", entry) + "\n");
#endif
    res=ldap->add(whatchanged->dn, entry);

    if(res) return res;

  }
  else
  { 
#ifdef DEBUG 
    werror("checking the user: " + dn + ".\n");
#endif
    ldap->set_basedn(whatchanged->dn);
    object rx=ldap->search("objectclass=*");
    if(rx->num_entries()==0) return 32; // no such user
    string uid=rx->fetch()["uid"][0];
    if(whatchanged->uid) // we need to change the userid.
    { 
      // first, check to see that the userid isn't already taken.
      ldap->set_basedn(ldap->BASEDN);
      string filter="(&(uid=" + whatchanged->uid +
        ")(objectclass=shadowaccount))";
#ifdef DEBUG
      werror("filter: " + filter + "\n");
#endif
      rx=ldap->search(filter, 0, ({"cn"}));
      if(rx->num_entries()) 
      {
        whatchanged->propertiesWindow->changed();
        openError("Username " + whatchanged->uid + " already exists.\nPlease choose another.");
        return 0;
      }
      // next, we need to update groups
      array newdn=(whatchanged->dn/",");
      newdn[0]="uid=" + whatchanged->uid;
      res=resolveDependencies(whatchanged->dn, newdn*",", ldap);
      // finally, update any auto_home directories
      string autohdn=getAutoHomeDN(uid, ldap);
      if(autohdn) // found one, so change it.
      { 
        res=ldap->modifydn(autohdn, "cn=" + whatchanged->uid, 1);
        if(res) return res;
        autohdn=getAutoHomeDN(whatchanged->uid, ldap);
        res=ldap->modify(autohdn, (["cn": ({2, whatchanged->uid})]));
        if(res) return res;
      }
      // then change the dn.
      res=ldap->modifydn(whatchanged->dn, "uid=" + whatchanged->uid, 1);
      if(res) return res;
      newdn=(whatchanged->dn/",");
      newdn[0]="uid=" + whatchanged->uid;
      whatchanged->dn=newdn*",";
      uid=whatchanged->uid;    
    }
  }
 
  if(!whatchanged->newObject && (wc["sn"] || wc["givenname"])) // we need to change the cn
  {
    res=fixcn(wc);
    if(res)
      return res;
  }

  if(sizeof(indices(wc))>0)
  { 
    int changetype=2; // replace
    foreach(indices(wc), string attr)
    {
      if(wc[attr]=="")
        change[attr]=({changetype});
      if(attr=="gidnumber")
      {

        if(arrayp(wc[attr]))
        {
            change[attr]=({changetype});
            foreach(wc[attr], string val)
              change[attr]+=({getGidfromName(val, ldap)});
        }
        else
	  change[attr]=({changetype, (string)getGidfromName(wc[attr], ldap)});
      }

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

    res=ldap->modify(dn, change);
    if(res) return res;
#ifdef DEBUG
   werror("done.\n");
#endif
  }

  if(whatchanged->useautohome==0 || whatchanged->useautohome==1) 
   // we want to change use of autohome
  {
    string autohomedirectorydn=getAutoHomeDN(uid, ldap);
    if(whatchanged->useautohome==0 && autohomedirectorydn) 
    {
      // we have an entry and we need to delete it.
#ifdef DEBUG
      werror("deleting the autohome record...");
#endif
      res=ldap->delete(autohomedirectorydn);
      if(res) return res;
#ifdef DEBUG
      werror("done.\n");
#endif
    }
    else if(whatchanged->useautohome==0 && !autohomedirectorydn)
    {
      // we don't have one and we don't want to use one.
    }
    else if(whatchanged->useautohome==1 && autohomedirectorydn)
    {
      // we want one, and we have one
#ifdef DEBUG
       werror("modifying the autohome directory record...");
#endif
       res=ldap->modify(autohomedirectorydn, ([ 
              "nismapentry": ({2, whatchanged->autohomedirectory})
              ]));
       if(res) return res;
#ifdef DEBUG
      werror("done.\n");
#endif
    }
    else if(whatchanged->useautohome==1 && !autohomedirectorydn)
    {
      // we don't have one, and we want one.
      autohomedirectorydn="cn=" + uid + ",nismapname=auto_home," + 
	ldap->BASEDN;
#ifdef DEBUG
      werror("adding auto_home entry for " + uid + ", dn=" +
         autohomedirectorydn + "...");
#endif
      res=ldap->add(autohomedirectorydn, ([ 
              "nismapentry": ({whatchanged->autohomedirectory}),
              "cn": ({uid}),
              "nismapname": ({"auto_home"}),
              "objectclass": ({"nisobject"})
              ]));
      if(res) return res;
#ifdef DEBUG
      werror("done.\n");
#endif
    }
  }
#ifdef DEBUG
  werror(sprintf("%O\n", change));
#endif
  return res;
}

string makecn(mapping wc)
{
    if(wc && !wc->sn) wc->sn=data->sn[0];
    if(wc && !wc->givenname) 
    {
      if(data->givenname)
        wc->givenname=data->givenname[0];
      else if(data->gn)
        wc->givenname=data->gn[0];
    }
    string fn;
    if(this->preferences->user_objects->cn=="firstnamefirst")
      fn=wc->givenname + " " + wc->sn; 
    else if(this->preferences->user_objects->cn=="lastnamefirst")
      fn=wc->sn + ", " + wc->givenname; 
    return fn;
} 

int fixcn(mapping wc)
{
    loadData();
    int res;
    string fn=makecn(wc);
    res=doRename(fn);
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
    if(checkUserChanges(whatchanged->dn, whatchanged))
      return;
    else res=doUserChanges(whatchanged->dn, whatchanged);
    if(res!=0)
    {
     
      ldap->ldap_errno=res;
      openError("An error occurred while modifying a user: " +
	"\n\n" + res + " " + ldap->error_string(res));
      widget->close();
      return;
    }   
    else 
    {
#ifdef DEBUG
      werror("user added successfully.\n");
#endif
      newuser=0;
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

void autoHomeToggled(object what, object widget, mixed ... args)
{
  if(widget->get_active()) 
  {
    what->show(); 
  }
  else 
  {
    what->hide();
  }
}

void autoHomeToggled2(mapping w, object widget, mixed ... args)
{
  if(widget->get_active()) 
  {
    w->useautohome=1;
  }
  else 
  {
    w->useautohome=0;
  }
}

void autoHomeToggled3(object what, object widget, mixed ... args)
{
  what->changed();
}

int addUsertoGroup(string uid, string userdn, string groupdn)
{
  if(uid=="" || userdn=="" || groupdn=="")  return 0;
  if(!uid || !userdn || !groupdn)  return 0;
  int res=ldap->modify(groupdn, (["memberuid": ({ 0, uid}),
			"uniquemember": ({ 0, userdn})
    ]));
  return res;
}

int removeUserfromGroup(string uid, string userdn, string groupdn)
{
  int res=ldap->modify(groupdn, (["memberuid": ({ 1, uid}),
			"uniquemember": ({ 1, userdn})
    ]));
  return res;
}

void loadData()
{
  if(dn=="") // we have a new object.
  {
    data=loadDefaults();
    return;
  }

  if(data) return;
  ldap->set_scope(2);
  ldap->set_basedn(dn);
  string filter="objectclass=*";
  object res=ldap->search(filter);
  string message=sprintf("%O", res->fetch());
  data=res->fetch();
}

mapping loadDefaults()
{
  string defaults=Stdio.read_file("defaults/" + type + ".dat");
  if(!defaults) throw("Unable to read defaults for object type " + type);
  data=decode_value(defaults);
#ifdef DEBUG
  werror("defaults: " + sprintf("%O", data) + "\n");
#endif
  return data;
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


  mapping info=([]);
  info=data;
  if(dn=="") 
  {
    whatchanged=info;
    newuser=1;
  }
  string cn1= getValue(info, "cn");

  // check for the proper objectclasses
  array roc=({"posixaccount", "shadowaccount", "person",
    "account", "inetorgperson", "organizationalperson", "mailrecipient"});

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
        ldap->modify(dn, (["objectclass": ({0, oc1})]));    
      }
    }
  }
  object propertiesWindow;
  propertiesWindow = Gnome.PropertyBox();
  propertiesWindow->set_title("Properties of user " + cn1);
  whatchanged->propertiesWindow=propertiesWindow;
  whatchanged->dn=dn;
  object generaltab=GTK.Vbox(0, 0);
  object sourcetab=GTK.Vbox(0, 0);
  object accounttab=GTK.Vbox(0, 0);
  object environmenttab=GTK.Vbox(0, 0);
  object mailtab=GTK.Vbox(0, 0);
  object groupstab=GTK.Vbox(0, 0);
  object titleline=GTK.Hbox(0, 5);
  object p=getPixmapfromFile("icons/user.png");
  object pic=GTK.Pixmap(GDK.Pixmap(p));
  titleline->pack_start_defaults(pic->show());
  titleline->pack_start_defaults(GTK.Label(cn1)->show());
  titleline->show();
  generaltab->pack_start(titleline,0,0,20);

// set up entry fields
  string tmp="";
  tmp=getTextfromEntry("sn", info);
  object sn=addProperty("sn", tmp, GTK.Entry());
  tmp=getTextfromEntry(({"gn", "givenname"}), info);
  object givenname=addProperty("givenname", tmp, GTK.Entry());
  tmp=getTextfromEntry("uid", info);
  object uid=addProperty("uid", tmp, GTK.Entry());
  tmp=getTextfromEntry("uidnumber", info);
  object uidnumber=addProperty("uidnumber", tmp, GTK.Entry());
  tmp=getTextfromEntry("gidnumber", info);
  if(tmp!="")
    tmp=getNamefromGid(tmp, ldap);
  // gidnumber contains the group _name_ not group id number.
  // we'll need to convert later back to gid before operating.
  object gidnumber=addProperty("gidnumber", tmp, Gnome.Entry());
  if(tmp=="") gidnumber->prepend_history(0, "");
  foreach(getGroupsforMember(0, ldap), array grp)
    gidnumber->prepend_history(0, grp[0]);
  tmp=getTextfromEntry("description", info);
  object description=addProperty("description", tmp, GTK.Entry());
  tmp=getTextfromEntry("loginshell", info);
  object loginshell=addProperty("loginshell", tmp, Gnome.Entry());
  loginshell->set_usize(120,0);
  array shells=({});
  if(file_stat("/etc/shells"))
    shells=Stdio.read_file("/etc/shells")/"\n";
  else shells=({"/bin/sh", "/bin/ksh", "/bin/csh"});
  foreach(shells, string s)
    loginshell->prepend_history(0, s);
  tmp=getTextfromEntry("mail", info);
  object mail=addProperty("mail", tmp, GTK.Entry());
  tmp=getTextfromEntry("homedirectory", info);
  object homedirectory=addProperty("homedirectory", tmp, GTK.Entry());
  // we will set the value for autohomedirectory later.
  object autohomedirectory=addProperty("autohomedirectory", "", GTK.Entry());
  tmp=getTextfromEntry("shadowmax", info);
  object shadowmax=addProperty("shadowmax", tmp, GTK.Entry());
  tmp=getTextfromEntry("shadowmin", info);
  object shadowmin=addProperty("shadowmin", tmp, GTK.Entry());
  tmp=getTextfromEntry("shadowwarning", info);
  object shadowwarning=addProperty("shadowwarning", tmp, GTK.Entry());
  tmp=getTextfromEntry("shadowexpire", info);
  object shadexp=Gnome.DateEdit(time(), 0, 1);
  shadexp->set_usize(200,200);
  object shadowexpire=addProperty("shadowexpire", tmp, shadexp);
  tmp=getTextfromEntry("shadowinactive", info);
  object shadowinactive=addProperty("shadowinactive", tmp, GTK.Entry());
  tmp=getTextfromEntry("telephonenumber", info);


//   tmp=getTextfromEntry("shadowmax", info);
//   object shadowmax=addProperty("shadowmax", tmp, GTK.SpinButton(GTK.Adjustment(0.0, 0.0, 9999.0, 1.0), 1.0, 0)->set_usize(160,20));
//   tmp=getTextfromEntry("shadowmin", info);
//   object shadowmin=addProperty("shadowmin", tmp, GTK.SpinButton(GTK.Adjustment(5.0, 0.0, 9999.0, 1.0), 1.0, 0)->set_usize(150,20));
//   tmp=getTextfromEntry("shadowwarning", info);
//   object shadowwarning=addProperty("shadowwarning", tmp, GTK.SpinButton(GTK.Adjustment(0.0, 0.0, 90.0, 1.0), 1.0, 0)->set_usize(150,20));
//   tmp=getTextfromEntry("shadowexpire", info);
//   object shadexp=Gnome.DateEdit(time(), 0, 1);
//   shadexp->set_usize(200,200);
//   object shadowexpire=addProperty("shadowexpire", tmp, shadexp);
//   tmp=getTextfromEntry("shadowinactive", info);
//   object shadowinactive=addProperty("shadowinactive", tmp, GTK.SpinButton(GTK.Adjustment(0.0, 0.0, 9999.0, 1.0), 1.0, 0)->set_usize(60,20));
//   tmp=getTextfromEntry("telephonenumber", info);



  object telephonenumber=addProperty("telephonenumber", tmp, GTK.Entry());
  tmp=getTextfromEntry("mailforwardingaddress", info);
  object mailforwardingaddress=addProperty("mailforwardingaddress", tmp, GTK.Entry());
  object useautohome=GTK.CheckButton("Use Automount for Home");
  object objectsource=GTK.Text();
  array ag=getGroupsforMember(0, ldap);
  object allgroups=newGroupList(ag);
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
  shadowmin->set_usize(50,0);
  shadowmax->set_usize(50,0);
  shadowwarning->set_usize(50,0);
  shadowexpire->set_usize(50,0);
  shadowinactive->set_usize(50,0);
  description->set_usize(200,0);
  telephonenumber->set_usize(200,0);
  mail->set_usize(200,0);
  mailforwardingaddress->set_usize(200,0);
  homedirectory->set_usize(200,0);
  autohomedirectory->set_usize(200,0);
  objectsource->set_usize(250,250);
  
  sn->set_usize(200,0);
  givenname->set_usize(200,0);
  array gm=({});
  if(dn!="")
    gm=getGroupsforMember(info->uid[0], ldap);  
  foreach(gm, array ginfo)
  { 
    int row=groupmemberships->append(({"group",ginfo[0]+ " (" + ginfo[1]+")"}));
    row=groupmemberships->set_row_data(row, groupentry(ginfo[1], ginfo[2], ginfo[0]));
  }

  groupmemberships->sort();

  catch(objectsource->set_text(generateLDIF(info)));
  addItemtoPage(homedirectory, "Home Directory", environmenttab);
  addItemtoPage(givenname, "First Name", generaltab);
  addItemtoPage(sn, "Last Name", generaltab);
  addItemtoPage(uid, "Username", accounttab);
  addItemtoPage(description, "Description", generaltab);
  addItemtoPage(uidnumber, "Numeric User ID" + ((dn=="")?" (optional)":""), accounttab);
  addItemtoPage(gidnumber, "Primary Group", accounttab);
  addItemtoPage(mail, "Mail Address", mailtab);
  addItemtoPage(mailforwardingaddress, "Deliver Mail To", mailtab);
  addItemtoPage(loginshell, "Login Shell", accounttab);
  addItemtoPage(telephonenumber, "Telephone Number", generaltab);
  environmenttab->pack_start(useautohome->show(),0,0,4);
  object amh=addItemtoPage(autohomedirectory, "AutoMount Home From", environmenttab);
  amh->hide();
  useautohome->signal_connect("toggled", autoHomeToggled, amh);
  useautohome->signal_connect("toggled", autoHomeToggled2, whatchanged);
  useautohome->signal_connect("toggled", autoHomeToggled3, propertiesWindow);
  addItemtoPage(shadowmax, "Max Password Life", environmenttab);
  addItemtoPage(shadowmin, "Min Password Life", environmenttab);
  addItemtoPage(shadowwarning, "Password Warning (Days)", environmenttab);
  addItemtoPage(shadowexpire, "Expire account after date", environmenttab);
  addItemtoPage(shadowinactive, "Lock account after inactivity (Days)", environmenttab);
  object hb2=GTK.Hbox(0,0);
  object vb1=GTK.Vbox(0,0);
  object vb2=GTK.Vbox(0,0);
  object vb3=GTK.Vbox(0,0);

  object addbutton=GTK.Button(" < ");
  object removebutton=GTK.Button(" > ");
  addbutton->signal_connect("clicked", lambda(object what, object widget,
mixed ... args){
if(newuser)
{
  openError("Click Apply to add the user before adding it to a group.");
  return;
}
array selection=allgroups->allgroups->get_selection();
foreach(selection, int row)
  {
    object d=allgroups->allgroups->get_row_data(row);
#ifdef DEBUG
    werror("adding group membership: " + d->dn + " for user " + info["uid"][0] + "\n");
#endif
    int res=addUsertoGroup(info["uid"][0], info["dn"][0], d->dn);
    if(res) openError("An error occurred while adding a group membership:\n\n" + ldap->error_string(res));
    else
    {
      groupmemberships->freeze();
      int row=groupmemberships->append(({"group",d->description + " (" +
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
array selection=groupmemberships->get_selection();
foreach(selection, int row)
  {
    object d=groupmemberships->get_row_data(row);
#ifdef DEBUG
    werror("removing group membership: " + d->dn + " for user " + info["uid"][0] + "\n");
#endif
    int res=removeUserfromGroup(info["uid"][0], info["dn"][0], d->dn);
    if(res) openError("An error occurred while removing a group membership:\n\n" + ldap->error_string(res));
    else
    {
      int row=groupmemberships->remove(row);
    }
  }
}
,groupmemberships);
  
  vb2->pack_start(addbutton->show(),0,15,15);
  vb2->pack_start(removebutton->show(),0,15,15);
  vb1->pack_start_defaults(GTK.Label("Current Memberships")->show());
  vb3->pack_start_defaults(GTK.Label("Available Groups")->show());
  vb1->pack_start_defaults(hb3->show());
  vb3->pack_start_defaults(allgroups->hb4->show());
  groupmemberships->show();
  hb2->pack_start(vb1->show(),0,15,15);
  hb2->pack_start(vb2->show(),0,15,15);
  hb2->pack_start(vb3->show(),0,15,15);
  groupstab->pack_start(hb2->show(),0,15,15);
  sourcetab->pack_start_defaults(objectsource->show());
  sourcetab->show();
  // attach changed signal to all entry widgets...

  sn->signal_connect("changed", propertiesChanged, whatchanged);
  givenname->signal_connect("changed", propertiesChanged, whatchanged);
  homedirectory->signal_connect("changed", propertiesChanged, whatchanged);
  uid->signal_connect("changed", propertiesChanged, whatchanged);
  uidnumber->signal_connect("changed", propertiesChanged, whatchanged);
  gidnumber->gtk_entry()->signal_connect("changed", propertiesChanged, whatchanged);
  mail->signal_connect("changed", propertiesChanged, whatchanged);
  mailforwardingaddress->signal_connect("changed", propertiesChanged, whatchanged);
  loginshell->entry()->signal_connect("changed", propertiesChanged, whatchanged);
  autohomedirectory->signal_connect("changed", propertiesChanged, whatchanged);
  shadowmax->signal_connect("changed", propertiesChanged, whatchanged);
  shadowmin->signal_connect("changed", propertiesChanged, whatchanged);
  shadowwarning->signal_connect("changed", propertiesChanged, whatchanged);
  description->signal_connect("changed", propertiesChanged, whatchanged);
  telephonenumber->signal_connect("changed", propertiesChanged, whatchanged);
  propertiesWindow->signal_connect("apply", applyProperties, whatchanged);


  // find out if we have an autohome directory
  string autohomedirectorydn;
  string filter1="(&(objectclass=nisobject)(cn=" +
     uid->get_text() + "))";
  ldap->set_basedn(ldap->BASEDN);
  object r=ldap->search(filter1);
  if(r->num_entries()>0)
  { 
#ifdef DEBUG
    werror("got an auto_home directory!\n");
#endif
    mapping rs=r->fetch();
    autohomedirectorydn=rs["dn"][0];
    autohomedirectory->set_text(rs["nismapentry"][0]);
    useautohome->set_active(1);
    useautohome->toggled();
  }
  werror(sprintf("%O\n", sort(indices(groupstab))));
//  generaltab->show();
  addPagetoProperties(generaltab, "General", propertiesWindow);
  addPagetoProperties(accounttab, "Account", propertiesWindow);
  addPagetoProperties(environmenttab, "Environment", propertiesWindow);
  addPagetoProperties(groupstab, "Groups", propertiesWindow);
  addPagetoProperties(mailtab, "Mail", propertiesWindow);
  addPagetoProperties(sourcetab, "Object Definition", propertiesWindow);
  if(newuser)
    groupstab->hide();

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
  int res=ldap->modifydn(dn, newrdn, 1, newrdn+","+new->dn);
  return res; // non-zero if failure.
}

int doEnable(string password)
{
  int res;
  mapping change=(["userpassword":({2, password }),
			"shadowlastchange": ({2,
                                   (string)(time()/(60*60*24))}) 
		]);

  res=ldap->modify(dn, change);

#ifdef DEBUG
  werror(sprintf("%O\n", change));
#endif
  return res;
}

int doPassword(string password)
{
  int res;
  mapping change=(["userpassword":({2, password }),
			"shadowlastchange": ({2,
                                   (string)(time()/(60*60*24))}) 
		]);

  res=ldap->modify(dn, change);

#ifdef DEBUG
  werror(sprintf("%O\n", change));
#endif
  return res;
}

int doRename(string fn)
{
  string firstcomp=(dn/"=")[0];
  firstcomp-=" ";
  int res;
  res=ldap->modify(dn, (["gecos":({2, fn})]));
  if(res) return res;
  res=ldap->modify(dn, (["cn":({2, fn})]));
  if(res) return res;
  string newrdn="cn=" + fn;
  if(firstcomp=="cn")  // we have to modify the dn as well.
  {
    string newdn=({newrdn, (dn/",")[1..]})*",";
    int res=ldap->modifydn(dn, newrdn, 1);
    if(res) // sucess code should be 0
    {
      return res; 
    }
    else
    {
      int res=resolveDependencies(dn, newdn, ldap);    
    }
  }
  cn=fn; // set the object cn to our new name.
  return res;
}

int doDisable()
{
  int res=ldap->modify(dn, (["userpassword":({2, "{crypt}*LK*"})]));
  return res;
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
  werror(sprintf("%O\n", r->fetch()));
#endif
  array rx=r->fetch();
  if(rx->uid)
  {
    string uid=rx["uid"][0];
  array groups=getGroupsforMember(uid, ldap);
  foreach(groups, string g)
  {
    werror("deleting " + uid + ", " + dn + " from group " + g[2] + ".\n");
    ldap->modify(g[2], (["uniquemember": ({1, dn}), "memberuid": ({1, uid})]));
  }
  string ahdn=getAutoHomeDN(uid, ldap);
  int res;
  if(ahdn)
  {
    res=ldap->delete(ahdn);
    if(res) 
      return res;
  }
  res=ldap->delete(dn);
  return res;
  }
  else werror("Unable to find userid for " + dn + "\n");
}

void openDisable()
{
  int res=doDisable();
  if(res!=0) 
  {
    openError("An error occurred while trying to "
      "disable an user:\n\n User: " + cn + "\n\n" +
      ldap->error_string(res));
    return;        
  }
  else this->refreshView();
  return;
}

void openDelete()
{
  int res=doDelete();
  if(res!=0)
    openError("An error occurred while trying to "
      "delete an user:\n\n User: " + cn + "\n\n" +
      ldap->error_string(res));
  else   this->refreshView();
  return;        
}

void openAddtoGroup()
{
  string groupdn;
  object addWindow=Gnome.Dialog("Add " + cn + " to a group...",
  GTK.GNOME_STOCK_BUTTON_OK, GTK.GNOME_STOCK_BUTTON_CANCEL);
  object vbox=addWindow->vbox();
  array ag=getGroupsforMember(0, ldap);

  object allgroups=newGroupList(ag);
  vbox->pack_start(GTK.Label("Choose a group to add " + cn + 
	" to:")->show(), 0,0,0);
  vbox->pack_start(allgroups->hb4->show(),0,0,0);
  addWindow->show();
  int res=addWindow->run();
  if(res==1);
  else 
  {
    array sr=allgroups->allgroups->get_selection();
#ifdef DEBUG
    werror(sprintf("selection: %O\n", sr));
#endif
    if(sizeof(sr)!=1);
    else 
    {
      object selectedgroup=allgroups->allgroups->get_row_data(sr[0]);
#ifdef DEBUG
        werror("adding group for " + uid + "\n");
#endif
        int res=addUsertoGroup(uid, dn, selectedgroup->dn);
        if(res!=0) 
        {
          openError("An error occurred while trying to "
   	  "add the following user to a group:\n\n User: " + cn + "\n\n" +
  	ldap->error_string(res));
//          refreshView();
          return;        
        }
    }
  }
  if(res !=-1)
    addWindow->close();
}

void openEnable()
{
  string txt;
  txt=cn;
  if(state!="locked")
  {
    openError("You may only enable disabled users.");
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
      if(res!=0) 
      {
          openError("An error occurred while trying to "
   	    "enable a user:\n\n User: " + cn + "\n\n" +
            ldap->error_string(res));
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
  txt=cn;
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
   	    "change a user's password:\n\n User: " + cn + "\n\n" +
            ldap->error_string(res));
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
  txt=cn;
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
   	"move an item:\n\n" +
	ldap->error_string(res));
      }
      else this->refreshView();
    moveWindow->close();
  }
  else if (res==1) moveWindow->close();
}

