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

constant cvs_version="$Id: hdadmin.pike,v 1.4 2002-02-03 20:58:15 hww3 Exp $";

import GTK.MenuFactory;

string ROOTDN, ROOTPW, LDAPHOST;
string BASEDN;

#define SSL3_DEBUG 1

object ldap;
object win,status,leftpane,rightpane;
object actions;

int isConnected=0;
object treeselection;
mapping treedata=([]);
int main(int argc, string* argv) {

 if(file_stat( getenv("HOME")+"/.pgtkrc" ))
    GTK.parse_rc( cpp(Stdio.read_bytes(getenv("HOME")+"/.pgtkrc")) );
Gnome.init("HDAdmin", "0.1", argv);
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

  array selected=rightpane->get_selected_icons();

  foreach(selected, int sel) 
  {
    object data=rightpane->get_icon_data(sel);
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
  array selected=rightpane->get_selected_icons();
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
  host->set_usize(200,0);
  basedn->set_usize(200,0);
  username->set_usize(200,0);
  password->set_usize(200,0);
  connectWindow->editable_enters(password);  
  // load default server uri(s) into host box.

  mapping conf=.readconf.readconf("/etc/ldap.conf");
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
      BASEDN=basedn->entry()->get_text();
    }
    if(res==-1) break;
    else if(res==1) break;
    else ROOTDN=u;
  }
  while(doConnect(h, u, p));
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

int doConnect(string host, string username, string password)
{
  if(isConnected==0)
  {
    object context=SSL.context();
    ldap=Protocols.LDAP.client(host, context);
    if(sizeof(username/"=")==1)  // we need to find the dn for uid
    {
      string filter1="(&(objectclass=account)(uid=" +
       username + "))";
      ldap->set_scope(2);
      ldap->set_basedn(BASEDN);
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
      werror("connecting as " + username + "\n");
    }
    int r=ldap->bind(username, password, 3);
    if(r!=0) {
      object c=Gnome.MessageBox("Login incorrect.",
      GTK.GNOME_MESSAGE_BOX_ERROR, GTK.GNOME_STOCK_BUTTON_OK);    
      c->set_usize(275, 150);
      c->show();
      c->run_and_close();
      return 1;
    }
    populateTree(leftpane, treedata);
    isConnected=1;
    return 0;
  }
  return 1;
}

void openAbout()
{
  object aboutWindow;
  aboutWindow = Gnome.About("HyperActive Directory Administrator",
				"0.1", "(c) Bill Welliver 2001",
				({"Bill Welliver", "The Unix God"}),
				"Manage your LDAP directory with style.",
				"icons/spiral.png");
  aboutWindow->show();
  return;
 }

void openProperties()
{
  array dns=getDNfromSelection();
  foreach(dns, object dn)
  {
    if(dn->type[0..3]=="user")
      openUserProperties(dn);
    else if(dn->type=="host")
      openHostProperties(dn);
    else openGenericProperties(dn);
  }

}

object addItemtoPage(object item, string desc, object page)
{
  object hbox=GTK.Hbox(0,0);
  object label=GTK.Label(desc+":");
  label->set_justify(GTK.JUSTIFY_RIGHT);
  hbox->pack_start(label->show(), 0, 0 , 5);
  hbox->pack_end(item->show(), 0, 0, 5);
  page->pack_start(hbox->show(), 0, 0, 4);
  return hbox;
}

object addPagetoProperties(object page, string desc, object properties)
{
  properties->append_page(page->show(), GTK.Label(desc)->show());
  return properties;
}

int isaNumber(string n)
{
  array ns=n/"";
  foreach(ns, string c)
    if(!Regexp("[0-9]")->match(c))
      return 0;
  return 1;
}

int checkUserChanges(string dn, mapping w)
{
  int i;
  string s;

  if(w->uid && w->uid=="")  // we have to have a username
  {
    openError("Username cannot be empty.");
    return 1;
  }
  if(w->homedirectory && w->homedirectory=="")  // we have to have a home directory
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
  if(w->uidnumber && !isaNumber(w->uidnumber))
  {
    openError("Numeric User ID must be a number.");
    return 1;
  }
  if(w->gidnumber && !isaNumber(w->gidnumber))
  {
    openError("Numeric Group ID must be a number.");
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
  return 0; // everything's fine  
}

string getAutoHomeDN(string uid)
{
  // find out if we have an autohome directory for this userid
  // werror("we're looking for an autohome entry for " + uid + "...\n");
  string autohomedirectorydn;
  string filter1="(&(objectclass=nisobject)(cn=" +
     uid + "))";
  ldap->set_basedn(BASEDN);
  object r=ldap->search(filter1);
  if(r->num_entries()>0)
  {
    autohomedirectorydn=r->fetch()["dn"][0];
  }
  return autohomedirectorydn;
}

int doUserChanges(string dn, mapping whatchanged)
{
  werror("doUserChanges for dn: " + dn + "\n");
  int res;
  mapping change=([]);
  werror(sprintf("Changes: %O\n", whatchanged));
  ldap->set_basedn(whatchanged->dn);
  object rx=ldap->search("objectclass=*");
  if(rx->num_entries()==0) return 32; // no such user
  string uid=rx->fetch()["uid"][0];
  if(whatchanged->uid) // we need to change the userid.
  { 
    // first, check to see that the userid isn't already taken.
    ldap->set_basedn(BASEDN);
    string filter="(&(uid=" + whatchanged->uid +
      ")(objectclass=shadowaccount))";
    werror("filter: " + filter + "\n");
    rx=ldap->search(filter, 0, ({"cn"}));
    if(rx->num_entries()) 
    {
      werror("Got a hit!\n");
      whatchanged->propertiesWindow->changed();
      openError("Username " + whatchanged->uid + " already exists.\nPlease choose another.");
      return 0;
    }
    // next, we need to update groups
    array newdn=(whatchanged->dn/",");
    newdn[0]="uid=" + whatchanged->uid;
    res=resolveDependencies(whatchanged->dn, newdn*",");
    // finally, update any auto_home directories
    string autohdn=getAutoHomeDN(uid);
    if(autohdn) // found one, so change it.
    { 
      res=ldap->modifydn(autohdn, "cn=" + whatchanged->uid, 1);
      if(res) return res;
      autohdn=getAutoHomeDN(whatchanged->uid);
      res=ldap->modify(autohdn, (["cn": ({2, whatchanged->uid})]));
      werror("done.");
      if(res) return res;
    }
    // then change the dn.
    res=ldap->modifydn(whatchanged->dn, "uid=" + whatchanged->uid, 1);
    if(res) return res;
    newdn=(whatchanged->dn/",");
    newdn[0]="uid=" + whatchanged->uid;
    whatchanged->dn=newdn*",";
    uid=whatchanged->uid;    
    refreshView();
  }

  mapping wc=copy_value(whatchanged);

  m_delete(wc, "dn");
  m_delete(wc, "useautohome");
  m_delete(wc, "autohomedirectory");
  m_delete(wc, "propertiesWindow");

  if(sizeof(indices(wc))>0)
  { 
    int changetype=2; // replace
    foreach(indices(wc), string attr)
    {
      if(wc[attr]=="")
        change[attr]=({changetype});
      else change[attr]=({changetype, wc[attr]});
    }
   werror(sprintf("change: %O\n", change));
   werror("changing attributes in main record...");
    res=ldap->modify(dn, change);
    if(res) return res;
   werror("done.\n");
  }

  if(whatchanged->useautohome==0 || whatchanged->useautohome==1) 
   // we want to change use of autohome
  {
    string autohomedirectorydn=getAutoHomeDN(uid);
    if(whatchanged->useautohome==0 && autohomedirectorydn) 
    {
      // we have an entry and we need to delete it.
      werror("deleting the autohome record...");
      res=ldap->delete(autohomedirectorydn);
      if(res) return res;
      werror("done.\n");
    }
    else if(whatchanged->useautohome==0 && !autohomedirectorydn)
    {
      // we don't have one and we don't want to use one.
    }
    else if(whatchanged->useautohome==1 && autohomedirectorydn)
    {
      // we want one, and we have one
       werror("modifying the autohome directory record...");
       res=ldap->modify(autohomedirectorydn, ([ 
              "nismapentry": ({2, whatchanged->autohomedirectory})
              ]));
       if(res) return res;
      werror("done.\n");
    }
    else if(whatchanged->useautohome==1 && !autohomedirectorydn)
    {
      // we don't have one, and we want one.
      autohomedirectorydn="cn=" + uid + ",nismapname=auto_home," + BASEDN;
      werror("adding auto_home entry for " + uid + ", dn=" +
         autohomedirectorydn + "...");
      res=ldap->add(autohomedirectorydn, ([ 
              "nismapentry": ({whatchanged->autohomedirectory}),
              "cn": ({uid}),
              "nismapname": ({"auto_home"}),
              "objectclass": ({"nisobject"})
              ]));
      if(res) return res;
      werror("done.\n");
    }
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
    werror("applyProperties: " + sprintf("%O\n", whatchanged));
    if(checkUserChanges(whatchanged->dn, whatchanged))
      return;
    else res=doUserChanges(whatchanged->dn, whatchanged);
    if(res!=0)
    {
      ldap->ldap_errno=res;
      openError("An error occurred while modifying a user: " +
"\n\n" + res + " " 
         + ldap->error_string(res));
      widget->close();
      return;
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

string generateLDIF(mapping info)
{
  string ldif="";
  if(!info->dn) return "ERROR: Incomplete object definition";
  mapping tmpinfo=copy_value(info);
  foreach(tmpinfo->dn, string value)
   ldif+=("dn: " + value + "\n");
  foreach(tmpinfo->objectclass, string value)
   ldif+=("objectclass: " + value + "\n");
  m_delete(tmpinfo, "dn");
  m_delete(tmpinfo, "objectclass");

  foreach(sort(indices(tmpinfo)), string index)
  {
    foreach(tmpinfo[index], string value)
    ldif+=(index + ": " + value + "\n");
  }
  return ldif;
}

void openUserProperties(object dn)
{
  ldap->set_scope(2);
  ldap->set_basedn(dn->dn);
  string filter="objectclass=*";
  object res=ldap->search(filter);
  string message=sprintf("%O", res->fetch());
  mapping info=res->fetch();
  string cn1=info["cn"][0];
  // check for the proper objectclasses
  array roc=({"posixaccount", "shadowaccount", "person",
    "account", "inetorgperson", "organizationalperson", "mailrecipient"});
  for(int i=0; i< sizeof(info["objectclass"]); i++)
  {
    info["objectclass"][i]=lower_case(info["objectclass"][i]);
  }
  foreach(roc, string oc1)
  {
    if(search(info["objectclass"], oc1)==-1)  // do we have this objectclass?
    {
      werror("adding objectclass " + oc1 + " for user " + dn->dn + "\n");
      ldap->modify(dn->dn, (["objectclass": ({0, oc1})]));    
    }
  }
//  werror(sprintf("%O\n", info));
  object propertiesWindow;
  mapping whatchanged=([]);
  propertiesWindow = Gnome.PropertyBox();
  propertiesWindow->set_title("Properties of user " + cn1);
  whatchanged->propertiesWindow=propertiesWindow;
  whatchanged->dn=dn->dn;
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
  object gidnumber=addProperty("gidnumber", tmp, GTK.Entry());
  tmp=getTextfromEntry("description", info);
  object description=addProperty("description", tmp, GTK.Entry());
  tmp=getTextfromEntry("loginshell", info);
  object loginshell=addProperty("loginshell", tmp, Gnome.Entry());
  loginshell->set_usize(120,0);
  foreach(Stdio.read_file("/etc/shells")/"\n", string s)
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
  object shadowexpire=addProperty("shadowexpire", tmp, GTK.Entry());
  tmp=getTextfromEntry("shadowinactive", info);
  object shadowinactive=addProperty("shadowinactive", tmp, GTK.Entry());
  tmp=getTextfromEntry("telephonenumber", info);
  object telephonenumber=addProperty("telephonenumber", tmp, GTK.Entry());
  tmp=getTextfromEntry("mailforwardingaddress", info);
  object mailforwardingaddress=addProperty("mailforwardingaddress", tmp, GTK.Entry());
  object useautohome=GTK.CheckButton("Use Automount for Home?");
  object objectsource=GTK.Text();
  array ag=getGroupsforMember();
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
  array gm=getGroupsforMember(info->uid[0]);  
  foreach(gm, array ginfo)
  { 
    int row=groupmemberships->append(({"group",ginfo[0]+ " (" + ginfo[1]+")"}));
    row=groupmemberships->set_row_data(row, groupentry(ginfo[1], ginfo[2], ginfo[0]));
  }

  groupmemberships->sort();

  objectsource->set_text(generateLDIF(info));
  addItemtoPage(homedirectory, "Home Directory", environmenttab);
  addItemtoPage(givenname, "First Name", generaltab);
  addItemtoPage(sn, "Last Name", generaltab);
  addItemtoPage(uid, "Username", accounttab);
  addItemtoPage(description, "Description", generaltab);
  addItemtoPage(uidnumber, "Numeric UserID", accounttab);
  addItemtoPage(gidnumber, "Numeric GroupID", accounttab);
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
  gidnumber->signal_connect("changed", propertiesChanged, whatchanged);
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
  ldap->set_basedn(BASEDN);
  object r=ldap->search(filter1);
  if(r->num_entries()>0)
  { 
    werror("got an auto_home directory!\n");
    mapping rs=r->fetch();
    autohomedirectorydn=rs["dn"][0];
    autohomedirectory->set_text(rs["nismapentry"][0]);
    useautohome->set_active(1);
    useautohome->toggled();
  }


//  generaltab->show();
  addPagetoProperties(generaltab, "General", propertiesWindow);
  addPagetoProperties(accounttab, "Account", propertiesWindow);
  addPagetoProperties(environmenttab, "Environment", propertiesWindow);
  addPagetoProperties(groupstab, "Groups", propertiesWindow);
  addPagetoProperties(mailtab, "Mail", propertiesWindow);
  addPagetoProperties(sourcetab, "Object Definition", propertiesWindow);
  propertiesWindow->show();
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
      werror("adding objectclass " + oc1 + " for host " + dn->dn + "\n");
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

void openGenericProperties(object dn)
{
  ldap->set_scope(2);
  ldap->set_basedn(dn->dn);
  string filter="objectclass=*";
  object res=ldap->search(filter);
  mapping info=res->fetch();

  // check for the proper objectclasses
  array roc=({});
  for(int i=0; i< sizeof(info["objectclass"]); i++)
  {
    info["objectclass"][i]=lower_case(info["objectclass"][i]);
  }
  foreach(roc, string oc1)
  {
    if(search(info["objectclass"], oc1)==-1)  // do we have this objectclass?
    {
      werror("adding objectclass " + oc1 + " for host " + dn->dn + "\n");
      ldap->modify(dn->dn, (["objectclass": ({0, oc1})]));    
    }
  }

  object propertiesWindow;
  propertiesWindow = Gnome.PropertyBox();
  propertiesWindow->set_title("Properties of object " + info->cn[0]);

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

int doMove(object orig, object new)
{
  string newrdn=(orig->dn/",")[0];
#ifdef DEBUG
  werror("getting ready to move " + newrdn + " to new dn: " + new->dn + "\n");
#endif
  int res=ldap->modifydn(orig->dn, newrdn, 1, newrdn+","+new->dn);
  return res; // non-zero if failure.
}

int doEnable(string dn, string password)
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

int doPassword(string dn, string password)
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

array getGroupsforMember(string|void uid)
{ 
  werror("getGroupsforMember");
  string filter;
  if(uid && uid!="") filter="(&(objectclass=posixgroup)(memberuid=" + uid+ "))";
  else filter="(objectclass=posixgroup)";
  werror(" filter: " + filter + "\n");
  array g=({});
  ldap->set_basedn(BASEDN);
  ldap->set_scope(2);
  object r=ldap->search(filter);
  if(r->num_entries()==0) return ({});

  else for(int i=0; i< r->num_entries(); i++)
  {
//   werror("got group...\n");
  string desc="";
  if(r->fetch()["description"])
    desc=r->fetch()["description"][0];
//    werror(sprintf("%O\n", r->fetch()));
    array gt=({r->fetch()["cn"][0], desc,
          r->fetch()["dn"][0]});
    g+=({gt}); 
    r->next();
  }
  return g;
}

int resolveDependencies(string dn, string newdn)
{
  // check to see if we have any group dependencies.
      
      string filter="(&(objectclass=posixgroup)(uniquemember=" + dn + "))";
      object r=ldap->search(filter, 1, ({"dn", "uniquemember"}));
      int nr=r->num_entries();
      if(nr>0) // we have affected groups...
      {
        // assume we are only changing the first item of the dn.
        for(int i=0; i<nr; i++)
        {
        mixed entry=r->fetch();
string uid=(((dn/",")[0])/"=")[1];
string newuid=(((newdn/",")[0])/"=")[1];
int res;
res=ldap->modify(entry["dn"][0],(["uniquemember": ({1, dn }), "memberuid": ({1, uid})]));
if(res) return res;
res=ldap->modify(entry["dn"][0],(["uniquemember": ({0, newdn }), "memberuid": ({0, newuid})]));
if(res) return res;
        r->next();
        }
      }
}
int doRename(object orig, string fn, string type)
{
  string firstcomp=(orig->dn/"=")[0];
  firstcomp-=" ";
  int res;
  if(type[0..3]=="user")
    res=ldap->modify(orig->dn, (["gecos":({2, fn})]));
  if(res) return res;
  res=ldap->modify(orig->dn, (["cn":({2, fn})]));
  if(res) return res;
  string newrdn="cn=" + fn;
  if(firstcomp=="cn")  // we have to modify the dn as well.
  {
    string newdn=({newrdn, (orig->dn/",")[1..]})*",";
    int res=ldap->modifydn(orig->dn, newrdn, 1);
    if(res) // sucess code should be 0
    {
      return res; 
    }
    else
    {
      int res=resolveDependencies(orig->dn, newdn);    
    }
  }
  return res;
}

void openMove(object o)
{
  array selected=rightpane->get_selected_icons();
  string txt;
  if(sizeof(selected)>1)
    txt=sizeof(selected) + " objects";
  else 
  {
    object data=rightpane->get_icon_data(selected[0]);
    txt=data->cn;
  }
  object moveWindow=Gnome.Dialog("Move " +  txt + "...",
    GTK.GNOME_STOCK_BUTTON_OK, GTK.GNOME_STOCK_BUTTON_CANCEL);
  mapping td=([]);
  object vbox=moveWindow->vbox();
  object t=makeTree();
  object s=GTK.ScrolledWindow(0,0);
  s->add(t->show());
  s->set_usize(275, 225);
  setupTree(t, td);
  populateTree(t, td);
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
    foreach(selected, int select)
    {
      object data=rightpane->get_icon_data(select);
      object newlocation=t->node_get_row_data(selection);
#ifdef DEBUG
      werror("old location: " + data->dn + "\n");
      werror("new location: " + newlocation->dn + "\n");
#endif
      res=doMove(data, newlocation);
      if(res!=0) 
      {
        openError("An error occurred while trying to "
   	"move an item:\n\n" +
	ldap->error_string(res));
      }
    }
    moveWindow->close();
  }
  else if (res==1) moveWindow->close();
}

void refreshView()
{
  if(current_selection)
    showIcons(0, leftpane, current_selection);
}

void openError(string msg)
{
  object errMsg=Gnome.MessageBox(msg,
    Gnome.MessageBoxError, Gnome.StockButtonCancel);    
  errMsg->set_usize(300, 175);
  errMsg->run();
}

void openRename(object o)
{
  array selected=rightpane->get_selected_icons();
  string txt;
  if(sizeof(selected)>1)
  {
    openError("You may only rename one object at a time.");
    return;
  }

  object data=rightpane->get_icon_data(selected[0]);
  txt=data->cn;

  object renameWindow=Gnome.Dialog("Move " +  txt + "...",
    GTK.GNOME_STOCK_BUTTON_OK, GTK.GNOME_STOCK_BUTTON_CANCEL);
  object vbox=renameWindow->vbox();
  mixed selection;
  object fn=GTK.Entry();
  fn->set_text(data->cn);
  addItemtoPage(fn, "Full Name", vbox);
  renameWindow->editable_enters(fn);
  vbox->show();
  renameWindow->show();
  int res=renameWindow->run();
  if(res==0)  // we clicked "ok"
  {
    object data=rightpane->get_icon_data(selected[0]);
    res=doRename(data, fn->get_text(), data->type);
    if(res!=0) 
    {
        openError("An error occurred while trying to "
   	"move an item:\n\n" +
	ldap->error_string(res));
    }
    else 
    {
       refreshView();
    } 
    renameWindow->close();   
  }
  else if (res==1) renameWindow->close();
}

int doDisable(string dn)
{
  int res=ldap->modify(dn, (["userpassword":({2, "{crypt}*LK*"})]));
  return res;
}

int doDelete(string dn)
{
  werror("deleting: " + dn + "\n");
  ldap->set_scope(2);
  ldap->set_basedn(dn);
  object r=ldap->search("objectclass=*");
  werror(sprintf("%O\n", r->fetch()));
  string uid=r->fetch()["uid"][0];
  array groups=getGroupsforMember(uid);
  foreach(groups, string g)
    ldap->modify(g, (["uniquemember": ({1, dn}), "memberuid": ({1, uid})]));
  string ahdn=getAutoHomeDN(uid);
  int res=ldap->delete(ahdn);
  if(res) 
    return res;
  res=ldap->delete(dn);
  return res;
}

void openDisable(object o)
{
  array selected=rightpane->get_selected_icons();
  string txt;
  foreach(selected, int sel)
  {
    object data=rightpane->get_icon_data(sel);
    txt=data->cn;
    if(data->type[0..3]!="user")
    {
      openError("You may only disable users.");
      return;
    }
  }
  foreach(selected, int sel)
  {
    object data=rightpane->get_icon_data(sel);
    int res=doDisable(data->dn);
    if(res!=0) 
    {
        openError("An error occurred while trying to "
   	"disable an user:\n\n User: " + data->cn + "\n\n" +
	ldap->error_string(res));
        refreshView();
        return;        
    }
  }
    refreshView();
}

void openDelete(object o)
{
  array selected=rightpane->get_selected_icons();
  string txt;
  foreach(selected, int sel)
  {
    object data=rightpane->get_icon_data(sel);
    txt=data->cn;
    if(data->type[0..3]!="user")
    {
      openError("You may only delete users.");
      return;
    }
  }
  
  foreach(selected, int sel)
  {
    object data=rightpane->get_icon_data(sel);
    int res=doDelete(data->dn);
    if(res!=0) 
    {
        openError("An error occurred while trying to "
   	"disable an user:\n\n User: " + data->cn + "\n\n" +
	ldap->error_string(res));
        refreshView();
        return;        
    }
  }
    refreshView();
}

class newGroupList
{

  object allgroups;
  object hb4;

  void create(array ga)
  {
  object adj2=GTK.Adjustment();  
  object scr2=GTK.Vscrollbar(adj2)->show();
  hb4=GTK.Hbox(0,0)->show();
  allgroups=GTK.Clist(2);
  allgroups->set_vadjustment(adj2);
  allgroups->set_usize(150,200);
  allgroups->set_sort_column(1);
  allgroups->set_sort_type(GTK.SORT_ASCENDING);
  allgroups->set_auto_sort(1);
  allgroups->show();
  hb4->pack_start_defaults(allgroups);
  hb4->pack_start_defaults(scr2);
  hb4->show();
  foreach(ga, array ginfo)
  {
    int row=allgroups->append(({"group", ginfo[0] + " (" + ginfo[1] + ")"}));
    allgroups->set_row_data(row, groupentry(ginfo[1], ginfo[2], ginfo[0]));
  }
  allgroups->sort();

  }
}

void openAddtoGroup(object o)
{
  array selected=rightpane->get_selected_icons();
  string txt;
  foreach(selected, int sel)
  {
    object data=rightpane->get_icon_data(sel);
    txt=data->cn;
    if(data->type!="user")
    {
      openError("You may only add users to groups.");
      return;
    }
  }
  if(sizeof(selected)>1) txt=sizeof(selected) + " users";
  string groupdn;
  object addWindow=Gnome.Dialog("Add " +  txt + " to a group...",
  GTK.GNOME_STOCK_BUTTON_OK, GTK.GNOME_STOCK_BUTTON_CANCEL);
  object vbox=addWindow->vbox();
  array ag=getGroupsforMember();

  object allgroups=newGroupList(ag);
  vbox->pack_start(GTK.Label("Choose a group to add " + txt + " to:")->show(), 0,0,0);
  vbox->pack_start(allgroups->hb4->show(),0,0,0);
  addWindow->show();
  int res=addWindow->run();
  if(res==1);
  else 
  {
    array sr=allgroups->allgroups->get_selection();
    werror(sprintf("selection: %O\n", sr));
    if(sizeof(sr)!=1);
    else 
    {
      werror("here we go!\n");
      object selectedgroup=allgroups->allgroups->get_row_data(sr[0]);
      foreach(selected, int sel)
      {
        object data=rightpane->get_icon_data(sel);
        werror("adding group for " + data->uid + "\n");
        int res=addUsertoGroup(data->uid, data->dn, selectedgroup->dn);
        if(res!=0) 
        {
          openError("An error occurred while trying to "
   	  "add the following user to a group:\n\n User: " + data->cn + "\n\n" +
  	ldap->error_string(res));
          refreshView();
          return;        
        }
      }
    }
  }
  if(res !=-1)
    addWindow->close();
}

void openEnable(object o)
{
  array selected=rightpane->get_selected_icons();
  if(sizeof(selected)>1)
  {
    openError("You may only enable one user at a time.");
    return;
  }
  string txt;
  object data=rightpane->get_icon_data(selected[0]);
  txt=data->cn;
  if(data->type!="user-locked")
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
        res=doEnable(data->dn, password->get_text());
      if(res!=0) 
      {
          openError("An error occurred while trying to "
   	    "enable a user:\n\n User: " + data->cn + "\n\n" +
            ldap->error_string(res));
          refreshView();
          return;        
      }
      else break;
    }
  }
  if(wres!=-1)
  {
    enableWindow->close();
    refreshView();
  }
}

void openPassword(object o)
{
  array selected=rightpane->get_selected_icons();
  string txt;
  if(sizeof(selected)>1)
  {
    openError("You may reset the password of one object at a time.");
    return;
  }

  object data=rightpane->get_icon_data(selected[0]);
  txt=data->cn;
  if(data->type!="user")
  {
    openError("You may only reset passwords for users.");
    return;
  }
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
        res=doPassword(data->dn, password->get_text());
      if(res!=0) 
      {
          openError("An error occurred while trying to "
   	    "change a user's password:\n\n User: " + data->cn + "\n\n" +
            ldap->error_string(res));
          refreshView();
          return;        
      }
      else break;
    }
  }
  if(res!=-1)
  {
    passwordWindow->close();
//    refreshView();
  }
}

object createPopupMenu(string type)
{
  array defs;
  // mapping sc = GTK.Util.parse_shortcut_file( "simple_menu_shortcuts" );
if(type=="user")
  defs = ({
    MenuDef( "New/User...", lambda(){werror("new user\n");}, 0),
    MenuDef( "New/Group...", openAbout, 0),
    MenuDef( "Properties...", openProperties, 0 ),
    MenuDef( "Delete...", openDelete, 0 ),
    MenuDef( "Move...", openMove, 0 ),
    MenuDef( "Reset Password...", openPassword, 0 ),
    MenuDef( "Disable Account", openDisable, 0 ),
    MenuDef( "Add user to Group...", openAddtoGroup, 0 ),
    MenuDef( "Rename", openRename, 0 ),
    MenuDef( "<separator>", 0, 0 ),
    MenuDef( "Help...", openAbout, 0 ),
  });
else if(type=="network")
  defs = ({
    MenuDef( "Properties...", openProperties, 0 ),
    MenuDef( "Delete...", openAbout, 0 ),
    MenuDef( "Move...", openMove, 0 ),
    MenuDef( "Rename", openRename, 0 ),
    MenuDef( "<separator>", 0, 0 ),
    MenuDef( "Help...", openAbout, 0 ),
  });
else if(type=="mailalias")
  defs = ({
    MenuDef( "Properties...", openProperties, 0 ),
    MenuDef( "Delete...", openAbout, 0 ),
    MenuDef( "Move...", openMove, 0 ),
    MenuDef( "Rename", openRename, 0 ),
    MenuDef( "<separator>", 0, 0 ),
    MenuDef( "Help...", openAbout, 0 ),
  });
else if(type=="group")
  defs = ({
    MenuDef( "Properties...", openProperties, 0 ),
    MenuDef( "Delete...", openAbout, 0 ),
    MenuDef( "Move...", openMove, 0 ),
    MenuDef( "Rename", openRename, 0 ),
    MenuDef( "<separator>", 0, 0 ),
    MenuDef( "Help...", openAbout, 0 ),
  });
else if(type=="user-locked")
  defs = ({
    MenuDef( "Properties...", openProperties, 0 ),
    MenuDef( "Delete...", openDelete, 0 ),
    MenuDef( "Move...", openMove, 0 ),
    MenuDef( "Enable Account...", openEnable, 0 ),
    MenuDef( "Rename", openRename, 0 ),
    MenuDef( "<separator>", 0, 0 ),
    MenuDef( "Help...", openAbout, 0 ),
  });
else if(type=="host")
  defs = ({
    MenuDef( "Properties...", openProperties, 0 ),
    MenuDef( "Delete...", openAbout, 0 ),
    MenuDef( "Move...", openMove, 0 ),
    MenuDef( "Rename", openRename, 0 ),
    MenuDef( "<separator>", 0, 0 ),
    MenuDef( "Help...", openAbout, 0 ),
  });
else if(type=="tree")
  defs = ({
    MenuDef( "Properties...", openProperties, 0 ),
    MenuDef( "Delete...", openAbout, 0 ),
    MenuDef( "New Org Unit...", openAbout, 0),
    MenuDef( "<separator>", 0, 0 ),
    MenuDef( "Help...", openAbout, 0 ),
  });
else if(type=="none")
  defs = ({
    MenuDef( "New/User...", lambda(){werror("new user\n");}, 0),
    MenuDef( "New/Group...", openAbout, 0),
    MenuDef( "New/Host...", openAbout, 0),
    MenuDef( "New/Alias...", openAbout, 0),
    MenuDef( "<separator>", 0, 0 ),
    MenuDef( "Help...", openAbout, 0 ),
  });
else defs = ({
    MenuDef( "Properties...", openProperties, 0 ),
    MenuDef( "Delete...", openAbout, 0 ),
    MenuDef( "Move...", openMove, 0 ),
    MenuDef( "Rename", openRename, 0 ),
    MenuDef( "<separator>", 0, 0 ),
    MenuDef( "Help...", openAbout, 0 ),
  });

  [object bar,object map] = PopupMenuFactory(@defs);
return bar;
//  return GTK.Menu()->append(bar);  
}

mixed newActionsPopup()
{
  array defs=({});

  if(isConnected && treeselection) defs+=
  ({
    MenuDef( "New User...", openAbout, 0 ),
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

object makeTree()
{
  object t=GTK.Ctree(1,0);
  return t;
}

void setupContent()
{
  object pane=GTK.Hpaned();
  object scroller1=GTK.ScrolledWindow(0,0);
  object scroller2=GTK.ScrolledWindow(0,0);
  leftpane=makeTree();
  rightpane=Gnome.IconList(40, 0);
  scroller1->add(leftpane);
  scroller2->add(rightpane);
  pane->set_position(200);
  pane->add1(scroller1);
  pane->add2(scroller2);
  scroller1->show();
  scroller2->show();
  leftpane->show();
  rightpane->set_separators(" ");
  rightpane->set_icon_width(65);
//  rightpane->set_col_spacing(55);
  rightpane->set_selection_mode(GTK.SELECTION_MULTIPLE);
  rightpane->show();
  win->set_contents(pane);
}

mapping clearTree(object t, mapping td)
{
  object c;
werror(sprintf("%O\n", indices(td->root)));  
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

object getPixmapfromFile(string filename)
{
  object p=Image.PNG.decode(Stdio.read_file(filename));
  return GDK.Pixmap(p);
}

void setupTree(object t, mapping td)
{
  object px=getPixmapfromFile("icons/spiral-sm.png");
  td->root=t->insert_node(0, 0, ({"HyperActive Directory"}), 0,
0);
  t->expand_recursive();
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
//  werror(sprintf("tree: %O\n", td));
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

mapping maptree(mapping td, array r, object tree)
{
  foreach(r, array row)  // look at each dn
  {
//   werror("mapping row: " + sprintf("%O", row[1]) + "\n");
     mapitem(td, row, tree, td->root, "");
  }
//  werror(sprintf("tree: %O\n", td));
  return td;
}

void populateTree(object t, mapping treedata)
{
  ldap->set_scope(2);
  ldap->set_basedn(BASEDN);

  string filter="objectclass=organizationalunit";
  object res=ldap->search(filter, 1, ({"dn"}));  

#ifdef DEBUG
  werror("got " + res->num_entries() + " orgs.\n");
#endif
  array tx=({});
  for(int i=0; i<res->num_entries(); i++) 
  {
    string dn=res->fetch()->dn[0];
#ifdef DEBUG
    werror("dn: " + dn + "\n");
#endif
    array name=dn/",";
    name=reverse(name);
    tx+=({ ({name, dn}) });      
    res->next();
  }
  treedata=maptree(treedata, tx, t);
  
#ifdef DEBUG
//  werror(sprintf("%O", treedata));
#endif
  
  t->expand_recursive();


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
  current_selection=selected;
  string t=widget->node_get_text(selected, 0);
  rightpane->clear();
  if(t=="HyperActive Directory") return;
  string type;
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
//  werror("name: " + nom + "\n");
    n+=({nom});
    ent+=({res->fetch()});
    res->next();
  }
  sort(n, ent);
  foreach(reverse(ent), mapping entry)
  {
    string item="_unknown_";
    catch(item=entry["cn"][0]);
    array oc=entry["objectclass"];
    string dn=entry["dn"][0];
#ifdef DEBUG
    werror("checking type of entry for " + item + "\n");
    werror(sprintf("%O", oc));
#endif
    if(search(oc, "posixAccount")>=0) type="user";
    else if(search(oc, "shadowaccount")>=0) type="user";
    else if(search(oc, "posixGroup")>=0) type="group";
    else if(search(oc, "ipNetwork")>=0) type="network";
    else if(search(oc, "nisMailAlias")>=0) type="mailalias";
    else if(search(oc, "ipHost")>=0) type="host";
    else type="unknown";
    if(type=="user" && entry["userpassword"] && 
      entry["userpassword"][0]=="{crypt}*LK*")
    {        type="user-locked";
//      werror("got a locked user!\n");
    }
    if(item && type[0..3]=="user")
      addIcon(([ "name": item, "type": type, "dn": entry["dn"][0], 
          "uid": entry["uid"][0] ]), rightpane);
    else
      addIcon((["name": item, "type": type, "dn": entry["dn"][0] ]), rightpane);
#ifdef DEBUG
werror("added item.\n");
#endif
  }
array dn2=({});
array dnc=(data->dn/",");
foreach(dnc, string d)
  dn2+=({(d/"=")[1]});
string ndn=reverse(dn2)*"/";
pushStatus("Viewing " + res->num_entries() + " items in " + ndn +
".\n");
clickevent=rightpane->signal_connect(GTK.button_press_event, clickIconList, 0);
rightpane->signal_connect("select_icon", selectIcon, 0);
rightpane->signal_connect("unselect_icon", unselectIcon, 0);

}

GTK.Menu popupmenu;
int menuisup=0;
int clickIconList(object what, object widget, mixed selected)
{ 
 if(menuisup==0 && popupmenu) popupmenu=0;
//rightpane->signal_disconnect(clickevent);

             if( selected->button == 3 ) {
array n=rightpane->get_selected_icons();
string otype;
if(sizeof(n)<1) otype="none";
else
{
  object data=rightpane->get_icon_data(n[0]);
  otype=data->type;
}
  if(!popupmenu)
  popupmenu = createPopupMenu(otype);
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

int clickDirectoryTree(object what, object widget, mixed selected)
{ 
 if(menuisup==0 && popupmenu) popupmenu=0;
//rightpane->signal_disconnect(clickevent);

             if( selected->button == 3 && treeselection) {
object data=leftpane->node_get_row_data(treeselection);
  if(!popupmenu)
  popupmenu = createPopupMenu("tree");
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
  array selection=rightpane->get_selected_icons();
//  werror(sprintf("%O", selection));
  foreach(selection, int icon)
  {
    object d=rightpane->get_icon_data(icon);
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

void addIcon(mapping item, object what)
{
  what->insert(0, "icons/" + item->type + "-sm.png", item->name);
  object d=iconentry(item->dn, item->name, item->type, (item->uid||""));
  what->set_icon_data(0, d);
}

class treeentry
{
  string name;
  string dn;
  void create(string n, string d)
  {
    dn=d;
    name=n;
  }
}

class iconentry
{
  string dn;
  string cn;
  string type;
  string uid;
  void create(string n, string c, string t, string|void u)
  {
    type=t;
    dn=n;
    cn=c;
    if(u)
      uid=u;
  }
}


class groupentry
{
  string name;
  string dn;
  string description;
  void create(string n, string d, string dc)
  {
    dn=d;
    description=dc;
    name=n;
  }

}
