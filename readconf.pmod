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
