import Parser.XML.Tree;

int main(int argc, array argv)
{
  string s=Stdio.stdin->read();
  Parser.XML.Tree tre=parse_input(s);

  tre->iterate_children(lambda(object n){if(n->get_tag_name()=="project") 
     parse_project(n, argv[1]);});

  return 0;
}

void parse_project(Node tree, string lang)
{
  foreach(tree->get_children(), Node node)
  {
    switch(node->get_tag_name())
    {
      case "str":
      {
	Node orig_node, trans_node;
	foreach(node->get_children(), Node child)
	{
	  if(child->get_tag_name()=="o")
	    orig_node=child;
	  if(child->get_tag_name()=="t")
	    trans_node=child;
	}
	trans_node->add_child(Node(XML_TEXT, "",
				   ([]),
				   translate(orig_node[0]->get_text(),
					     "en", lang)));
	break;
      }
      
      case "language":
      {
	node->replace_child(node[0],
			    Node(XML_TEXT, "", ([]), lang));
	break;
      }
    }
  }
  write("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"+tree->html_of_node());
}
    
string translate(string s, string from, string to)
{

  werror("%s",s);
  
s=Protocols.HTTP.post_url_data("http://translate.google.com/translate_t",
					(["oe": "utf8",
					  "text": s,
					  "langpair": from+"|"+to]));

  sscanf(s, "%*s<textarea %*s>%s</textarea>", s);

  werror(" -> %s\n",s);
  return s;
}


