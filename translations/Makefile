EXTRACT="pike -x extract_locale"

# do not alter
all: modules xmls translations

modules:
	@echo "1. Finding modules"
	@for a in `find ../Objects.pmod/ -name '*.pike'` ; do \
	  if grep -c '#!NO' $$a >/dev/null 2>&1; then \
	   :;\
          else  \
	    module='"mod_'`echo $$a|sed -e s',../Object.pmod/.*/,,' -e s',.pike,,'`'"';\
	    if grep -c "$$module" $$a >/dev/null 2>&1; then \
	      ./scripts/make_mod_config $$module $$a; \
	    fi;\
	  fi ; \
	done

xmls:
	@echo "2. Rebuilding .xml config files"
	@for a in configs/*.xml ; do  \
		pkg=`echo $$a | sed -e s',\.xml,,' -e s',.*/,,'`; \
		./scripts/make_config $$pkg configs/$$pkg.xml ; \
	done

translations:
	@echo "3. Rebuilding translation files"
	@for a in configs/*.xml ; do  \
		pkg=`echo $$a | sed -e s',\.xml,,' -e s',.*/,,'`; \
		./scripts/build_from_config  configs/$$pkg.xml $(EXTRACT); \
	done


clean:
	rm configs/*~
	rm configs/mod_*.xml

