/* Config file reader/writer
   Copyright 1998 by Bill Welliver
   hww3@riverweb.com
   
   This file may be used and distributed under the terms of the 
   GNU Public License version 2 or later.

*/

string format_section(string section, mapping attributes){
//  perror(section + ":\n" + sprintf("%O", attributes));
  string s="";
  
  s+="\n[" + section + "]\n";
  foreach(indices(attributes), string a) {
//        perror("attribute " + a + ", value " +attributes[a] +" \n");
       if(arrayp(attributes[a]))
            foreach(attributes[a], string v)
            s+=a + "=" + v + "\n";
        else s = s + a + "=" + (string)attributes[a] + "\n";
      }
  return s;

}

mapping read(string contents){
    mapping config=([]);
    string section,attribute,value;
    array c;
    if(contents)
        c=contents/"\n";
    else return ([]); 
    foreach(c, string line) {
        if((line-" ")[0..0]=="[") { // We've got a section header
            sscanf(line,"%*s[%s]%*s",section);
            if(!config[section])
                config[section]=([]);
        }
        if(sscanf(line,"%s=%s", attribute, value)==2) // attribute line.
            if(config[section][attribute] && arrayp(config[section][attribute]))
                config[section][attribute]+=({value});
            else if(config[section][attribute])
                config[section][attribute]=({config[section][attribute]}) + ({value});
            else config[section][attribute]=value;
    }
    return config;
}

string write(mapping config, array|void order){
    string s="# Configuration file.\n";
    array configs;
    if(!config) return s;
//perror(sprintf("%O", config));
    if(order) configs=order;
    else configs=indices(config);
    foreach(configs, string c){
//      perror("formatting section " + c + "\n");
//      perror("section values:\n " + sprintf("%O", config[c]) + "\n");

      s+= format_section(c, config[c]) +"\n";
    }

    return s;
}

array get_section_names(string contents){
array sections=({});

array c=contents/"\n";
string section="";

foreach(c, string line) {
  if(sscanf(line, "[%s]", section)==1)
    sections +=({section});
  }
return sections;

}

int write_section(string file, string section, mapping attributes){


  if(!(file || !section || !attributes))
    return -1;	// no information was provided.

  mapping cpy=read(Stdio.read_file(file));


  cpy[section]=attributes;

// perror("New config file::: \n " + sprintf("%O", cpy) + ".\n");


// perror("moving config file...\n");
  mv(file, file+"~");

//  array sections=get_section_names(contents);

// perror("here it is...\n");
// perror(write(cpy));

  Stdio.write_file(file, write(cpy));
  return 0;

}
