//
//
//  util.pike: utility functions
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

#include "config.h"

constant cvs_version="$Id: util.pike,v 1.10 2002-10-17 21:20:01 hww3 Exp $";

import GTK.MenuFactory;

class LDAPConn
{
  inherit Protocols.LDAP.client;

  string ROOTDN, ROOTPW, LDAPHOST;
  string USER, USERPASS;
  string BASEDN;

  int agressive_delete(mixed a)
  {
    int res;
    res=delete(a);
    mixed r=get_referrals();
    if(!res && r)
    {
      foreach(r, string ref)
      {
         werror("Attempting connection to " + ref + "...\n");
         object context=SSL.context();
         object lref;
         catch(lref=Protocols.LDAP.client(ref, context));
         if(!lref) continue;
         werror("Connected.\n");
         res=lref->bind(USER, USERPASS);
         if(!res) continue;
         werror("Bound.\n");
         lref->set_basedn(BASEDN);
         res=lref->delete(a);
         werror("Ran delete, res=" + res + ", error=" + 
             lref->error_number() + ".\n");
         if(res) return res;
         else continue;
      }
    }
    return res;
  }

  int agressive_add(mixed a, mixed b)
  {
    int res;
    res=add(a, b);
    mixed r=get_referrals();
    if(!res && r)
    {
      foreach(r, string ref)
      {
         werror("Attempting connection to " + ref + "...\n");
         object context=SSL.context();
         object lref;
         catch(lref=Protocols.LDAP.client(ref, context));
         if(!lref) continue;
         werror("Connected.\n");
         res=lref->bind(USER, USERPASS);
         if(!res) continue;
         werror("Bound.\n");
         lref->set_basedn(BASEDN);
         res=lref->add(a, b);
         werror("Ran delete, res=" + res + ", error=" + 
             lref->error_number() + ".\n");
         if(res) return res;
         else continue;
      }
    }
    return res;
  }

  int agressive_modify(string cdn, mapping change)
  {
    int res;
    res=modify(cdn, change);
    mixed r=get_referrals();
    if(!res && r)
    {
      foreach(r, string ref)
      {
         werror("Attempting connection to " + ref + "...\n");
         object context=SSL.context();
         object lref;
         catch(lref=Protocols.LDAP.client(ref, context));
         if(!lref) continue;
         werror("Connected.\n");
         res=lref->bind(USER, USERPASS);
         if(!res) continue;
         werror("Bound.\n");
         lref->set_basedn(BASEDN);
         res=lref->modify(cdn, change);
         werror("Ran modify, res=" + res + ", error=" + 
             lref->error_number() + ".\n");
         if(res) return res;
         else continue;
      }
    }
    return res;
  }

  int agressive_modifydn(mixed a, mixed b, mixed c)
  {
    int res;
    res=modifydn(a, b, c);
    mixed r=get_referrals();
    if(!res && r)
    {
      foreach(r, string ref)
      {
         werror("Attempting connection to " + ref + "...\n");
         object context=SSL.context();
         object lref;
         catch(lref=Protocols.LDAP.client(ref, context));
         if(!lref) continue;
         werror("Connected.\n");
         res=lref->bind(USER, USERPASS);
         if(!res) continue;
         werror("Bound.\n");
         lref->set_basedn(BASEDN);
         res=lref->modifydn(a, b, c);
         werror("Ran modifydn, res=" + res + ", error=" + 
             lref->error_number() + ".\n");
         if(res) return res;
         else continue;
      }
    }
    return res;
  }
}

mapping loadPreferences()
{
  mapping prefs=([]);

  string f="";
  if(file_stat("./hdadmin_defaults.conf"))
    f+=Stdio.read_file("./hdadmin_defaults.conf");
  if(file_stat("/etc/hdadmin.conf"))
    f+=Stdio.read_file("/etc/hdadmin.conf");
  if(file_stat(getenv("HOME") + "/.hdadmin.conf"))
    f+=Stdio.read_file(getenv("HOME") + "/.hdadmin.conf");

  prefs=.Config.read(f);
  
  return prefs;
}

void setupTree(object t, mapping td)
{
  object px=getPixmapfromFile("icons/spiral-sm.png");
  td->root=t->insert_node(0, 0, ({"HyperActive Directory"}), 0, 0);
  t->expand_recursive();
}

object makeTree()
{
  object t=GTK.Ctree(1,0);
  return t;
}

object makeEntry(object widget, string desc)
{
  object hbox=GTK.Hbox(0, 0);
  hbox->pack_start_defaults(GTK.Label(desc)->show());
  hbox->pack_start_defaults(widget->show());
  return hbox;
}

object addItemtoPage(object item, string desc, object page)
{
  object hbox=GTK.Hbox(0,0);
//werror("ADDITEMTOPAGE!\n");

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

int getGidfromName(string n, object ldap)
{
  string filter="(&(objectclass=posixgroup)(cn=" + n + "))";
  ldap->set_basedn(ldap->BASEDN);
  ldap->set_scope(2);
  object r=ldap->search(filter);
#ifdef DEBUG
  werror("getGidfromName: " + r->num_entries() + " rows\n");
#endif
  if(r->num_entries()==0)
   return -1;
  else return (int)(fix_entry(r->fetch())["gidnumber"][0]);
}

int getGidfromDN(string n, object ldap)
{
  string filter="(objectclass=posixgroup)";
  ldap->set_basedn(n);
  ldap->set_scope(0);
  object r=ldap->search(filter);
#ifdef DEBUG
  werror("getGidfromDN: " + r->num_entries() + " rows\n");
#endif
  if(r->num_entries()==0)
   return -1;
  else return (int)(fix_entry(r->fetch())["gidnumber"][0]);
}

array getUidfromUidnumber(string n, object ldap)
{
  string filter="(&(objectclass=posixaccount)(uidnumber=" + n + "))";
  ldap->set_basedn(ldap->BASEDN);
  ldap->set_scope(2);
  object r=ldap->search(filter);
  if(r->num_entries()==0)
   return ({});
  array g=({});
  for(int i=0; i<r->num_entries(); i++)
  {
    g+=({fix_entry(r->fetch())["cn"][0]});
    r->next();
  }
  return g;
}

array getGidfromGidnumber(string n, object ldap)
{
  string filter="(&(objectclass=posixgroup)(gidnumber=" + n + "))";
  ldap->set_basedn(ldap->BASEDN);
  ldap->set_scope(2);
  object r=ldap->search(filter);
  if(r->num_entries()==0)
   return ({});
  array g=({});
  for(int i=0; i<r->num_entries(); i++)
  {
    g+=({fix_entry(r->fetch())["cn"][0]});
    r->next();
  }
  return g;
}

string|int getNamefromGid(string g, object ldap)
{
  string filter="(&(objectclass=posixgroup)(gidnumber=" + g + "))";
  ldap->set_basedn(ldap->BASEDN);
  ldap->set_scope(2);
  object r=ldap->search(filter);
  if(r->num_entries()==0)
   return -1;
  else return (string)(fix_entry(r->fetch())["cn"][0]);
}

string|int getUidfromDN(string dn, object ldap)
{
  ldap->set_basedn(dn);
  ldap->set_scope(2);
  object r=ldap->search("objectclass=*");
  werror("getUidfromDN: " + r->num_entries() + " rows\n");
  if(r->num_entries()==0)
   return -1;
  else return (string)(fix_entry(r->fetch())["cn"][0]);
}

int isaNumber(string|array n)
{
  array ns;
  if(arrayp(n))
    ns=n[0]/"";
  else ns=n/"";
  foreach(ns, string c)
    if(!Regexp("[0-9]")->match(c))
      return 0;
  return 1;
}


string getAutoHomeDN(string uid, object ldap)
{
  // find out if we have an autohome directory for this userid
  // werror("we're looking for an autohome entry for " + uid + "...\n");
  string autohomedirectorydn;
  string filter1="(&(objectclass=nisobject)(cn=" +
     uid + "))";
  ldap->set_basedn(ldap->BASEDN);
  object r=ldap->search(filter1);
  if(r->num_entries()>0)
  {
    autohomedirectorydn=fix_entry(r->fetch())["dn"][0];
  }
  return autohomedirectorydn;
}


int removeUserfromGroup(string uid, string userdn, string groupdn, object ldap)
{
  int res=ldap->modify(groupdn, (["memberuid": ({ 1, uid}),
			"uniquemember": ({ 1, userdn})
    ]));
  if(!res) return ldap->error_number();
  else return 0;
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

array getGroupsforMember(string|void uid, object ldap)
{ 
#ifdef DEBUG
  werror("getGroupsforMember");
#endif
  string filter;
  if(uid && uid!="") filter="(&(objectclass=posixgroup)(memberuid=" + uid+ "))";
  else filter="(objectclass=posixgroup)";
#ifdef DEBUG
  werror(" filter: " + filter + "\n");
#endif
  array g=({});
  ldap->set_basedn(ldap->BASEDN);
  ldap->set_scope(2);
  object r=ldap->search(filter);
  if(r->num_entries()==0) return ({});

  else for(int i=0; i< r->num_entries(); i++)
  {
//   werror("got group...\n");
  mapping m=fix_entry(r->fetch());
  string desc="";
  if(m["description"])
    desc=m["description"][0];
    array gt=({m["cn"][0], desc,
          m["dn"][0], m["gidnumber"][0]});
    g+=({gt}); 
    r->next();
  }
  return g;
}

array getMembersofPrimaryGroup(string g, object ldap)
{
  array m=({});
  string filter="(&(objectclass=posixaccount)(gidnumber=" + g+ "))";
#ifdef DEBUG
  werror(" filter: " + filter + "\n");
#endif
  ldap->set_basedn(ldap->BASEDN);
  ldap->set_scope(2);
  object r=ldap->search(filter);
  if(r->num_entries()==0) return ({});
  for(int i=0; i< r->num_entries(); i++)
  {
    mapping m1=fix_entry(r->fetch());
    m+=({m1["uid"][0]});
  }
  return m;
}

array getMembersforGroup(string|void dn, object ldap)
{ 
#ifdef DEBUG
  werror("getMembersforGroup: " + dn + "\n");
#endif

  array g=({});
  string filter;
  if(dn && dn!="")
  {
     filter="objectclass=*";
#ifdef DEBUG
     werror(" filter: " + filter + "\n");
#endif
     ldap->set_basedn(dn);
     ldap->set_scope(0);
     object r=ldap->search(filter);
     if(r->num_entries()==0) return ({});
     mapping m1=fix_entry(r->fetch());
     if(m1["uniquemember"] && sizeof(m1["uniquemember"])>0)
       foreach(m1["uniquemember"], string mdn)
       {
#ifdef DEBUG
         werror("getting data for member " + mdn + "\n");
#endif
         filter="objectclass=*";
         ldap->set_basedn(mdn);
         ldap->set_scope(0);
         object r=ldap->search(filter);
         if(r->num_entries()==0) continue;
         mapping m=fix_entry(r->fetch());
         array gt=({m["uid"][0], m["cn"][0],
         m["dn"][0], m["uidnumber"][0]});
         g+=({gt}); 
         r->next();
       }
  }
  else
  {
     filter="(objectclass=posixaccount)";
#ifdef DEBUG
     werror(" filter: " + filter + "\n");
#endif
     ldap->set_basedn(ldap->BASEDN);
     ldap->set_scope(2);
     object r=ldap->search(filter);
     if(r->num_entries()==0) return ({});

     else for(int i=0; i< r->num_entries(); i++)
     {
       mapping m=fix_entry(r->fetch());
       string desc="";
       if(m["description"])
       desc=m["description"][0];
       array gt=({m["uid"][0], m["cn"][0],
          m["dn"][0], m["uidnumber"][0]});
       g+=({gt}); 
       r->next();
    }
  }
  return g;
}

mapping fix_entry(mapping orig)
{
  foreach(indices(orig), string att)
  {  
    if(att!=lower_case(att))
    {
      orig[lower_case(att)]=orig[att];
      m_delete(orig, att);
    }
  }

  return orig;
}
int resolveDependencies(string dn, string newdn, object ldap)
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
        mixed entry=fix_entry(r->fetch());
string uid=(((dn/",")[0])/"=")[1];
string newuid=(((newdn/",")[0])/"=")[1];
int res;
res=ldap->modify(entry["dn"][0],(["uniquemember": ({1, dn }), "memberuid": ({1, uid})]));
if(!res) return ldap->error_number();
res=ldap->modify(entry["dn"][0],(["uniquemember": ({0, newdn }), "memberuid": ({0, newuid})]));
if(!res) return ldap->error_number();
        r->next();
        }
      }
}

void openError(string msg)
{
  object errMsg=Gnome.MessageBox(msg,
    Gnome.MessageBoxError, Gnome.StockButtonOk, Gnome.StockButtonCancel);    
  errMsg->set_usize(325, 175);
  errMsg->run();
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


class newMemberList
{

  object allmembers;
  object hb4;

  void create(array ga)
  {
  object adj2=GTK.Adjustment();  
  object scr2=GTK.Vscrollbar(adj2)->show();
  hb4=GTK.Hbox(0,0)->show();
  allmembers=GTK.Clist(2);
  allmembers->set_vadjustment(adj2);
  allmembers->set_usize(150,200);
  allmembers->set_sort_column(1);
  allmembers->set_sort_type(GTK.SORT_ASCENDING);
  allmembers->set_auto_sort(1);
  allmembers->show();
  hb4->pack_start_defaults(allmembers);
  hb4->pack_start_defaults(scr2);
  hb4->show();
  foreach(ga, array ginfo)
  {
    int row=allmembers->append(({"user", ginfo[1] + " (" + ginfo[0] + ")"}));
    allmembers->set_row_data(row, userentry(ginfo[0], ginfo[2], ginfo[1]));
  }
  allmembers->sort();

  }
}

mapping pixmapcache=([]);


object getPixmapfromFile(string filename)
{
  if(pixmapcache[filename])
    return pixmapcache[filename];
  else
  {
    object p=Image.PNG.decode(Stdio.read_file(filename));
    pixmapcache[filename]=p;
    return GDK.Pixmap(p);
  }
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

class userentry
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

void populateTree(object t, mapping treedata, object ldap)
{
  ldap->set_scope(2);
  ldap->set_basedn(ldap->BASEDN);

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

