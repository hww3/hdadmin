//
//
//  readconf.pmod: A Pike module for reading ldap.conf configuration
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

constant cvs_version="$Id";

mapping readconf(string file)
{
  mapping configuration=([]);

  if(!file && !file_stat(file)) 
    return (["error": "No file provided or file not found!"]);

  array directives=({});
  array contents=Stdio.read_file(file)/"\n";

  // now we filter out the comments.
  foreach(contents, string line)
    if(line[0..0]=="#" || line[0..0]=="" || line[0..0]==" ") continue;
    else directives+=({line});

  foreach(directives, string d)
  {
    d=replace(d, "\t", " ");
    array d2=((d/" ")-({""}));
    configuration[d2[0]]=d2[1..]*(" ");    
  }
if(configuration->host) configuration->host=(configuration->host/" ")-({""});
if(configuration->uri) configuration->uri=(configuration->uri/" ")-({""});
  return configuration;
}


string get_base_dn(mapping configuration)
{
  if(configuration->base)
    return configuration->base;
  else return "";
}

array get_conn_info(mapping configuration)
{
  array c=({});
  if(configuration->uri)
    return (configuration->uri);
  else if(configuration->host)
  {
    foreach(configuration->host, string h)
    {
      string conn="ldap";
      if(configuration->ssl && configuration->ssl[0]!="no")
         conn+="s";  
       conn+="://";
       conn+=h;
       if(configuration->port)
         conn+=(":" + configuration->port);
       c+=({conn});
    }
    
    return c;
  }
  else return ({});
}
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

