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

constant cvs_version="$Id: generic.pike,v 1.1 2002-04-29 23:39:45 hww3 Exp $";

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

void create(object l, object th, string n, string c, string t, string|void 
u)
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


void openProperties()
{
  ldap->set_scope(2);
  ldap->set_basedn(dn);
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
#ifdef DEBUG
      werror("adding objectclass " + oc1 + " for host " + dn + "\n");
#endif
      ldap->modify(dn, (["objectclass": ({0, oc1})]));
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
  propertiesWindow->show();
  return;
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
    MenuDef( "Move...", openMove, 0),
  });
             
  return defs;
              
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
      "delete an object: " + cn + "\n\n" +
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
  return res; // non-zero if failure.
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
  return res; 
  }
  else werror("Unable to find object " + dn + "\n");
}


