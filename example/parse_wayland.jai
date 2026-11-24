main :: () {
    s := read_entire_file("/usr/share/wayland/wayland.xml");

    xml := parse_xml(s);
}

#import,dir "../";
#import "File";
#import "Basic";
