SRC ?= main.c forest-fire.c

SRCDIR ?= .
OBJDIR ?= .objdir
DEPDIR ?= .depdir

##########
# less important stuff
SHELL := /bin/sh
MKDIR ?= mkdir
RMDIR ?= rmdir

COLOR = echo -en '\e[1;34m'
RESET = echo -en '\e[0m'

##########
# warnings

# enable a lot of warnings and then some more
WARNINGS := -Wall -Wextra
# shadowing variables, are you sure?
WARNINGS += -Wshadow
# sizeof(void)
WARNINGS += -Wpointer-arith
# unsafe pointer cast qualifiers: `const char*` is cast to `char*`
WARNINGS += -Wcast-qual
# most of the time you don't want this
WARNINGS += -Werror=implicit-function-declaration
# let's stick with C89
# WARNINGS += -Werror=declaration-after-statement
# why warning for comments inside comments
WARNINGS += -Wno-comment

# be more strict
ifeq ($(shell $(CC) -dumpversion),4.7)
	# welcome to 2012
	# -Wpedantic is available since gcc 4.8
	WARNINGS += -pedantic
else
	WARNINGS += -Wpedantic
endif

# functions should be declared
#WARNINGS += -Wmissing-declarations

# C-specific warnings
CWARNINGS := $(WARNINGS)
# warn about fn() instead of fn(void)
CWARNINGS += -Werror=strict-prototypes
# this probably should be enabled only in bigger projects
#CWARNINGS += -Wmissing-prototypes

# standards (ANSI C, ANSI C++)
CFLAGS ?= $(CWARNINGS) -std=c11 -O2 -fstack-protector-strong
CXXFLAGS ?= $(WARNINGS) -std=c++14 -O2 -fstack-protector-strong
# for future use if needed
DEPFLAGS ?=
LDFLAGS ?= -lm
LDFLAGS += -s

##########

# add unicode support
CFLAGS += $(shell pkg-config --cflags-only-I icu-uc icu-io)
CXXFLAGS += $(shell pkg-config --cflags-only-I icu-uc icu-io)
LDFLAGS += $(shell pkg-config --libs-only-l --libs-only-L icu-uc icu-io)

EXE := $(basename $(firstword $(SRC)))

OBJ := $(addprefix $(OBJDIR)/, \
	$(addsuffix .o, $(SRC)) \
)

DEP := $(addprefix $(DEPDIR)/, \
	$(addsuffix .d, $(SRC)) \
)

STYLE := $(filter %.c %.h %.cpp %.hpp,$(SRC))

STYLED := $(addprefix $(DEPDIR)/, \
	$(addsuffix .styled, $(STYLE)) \
)

# be silent unless VERBOSE
ifndef VERBOSE
.SILENT: ;
endif

# template for inline assembler
define INCBIN
  .section @file@, "a"
  .global @sym@_start
@sym@_start:
  .incbin "@file@"
  .global @sym@_end
@sym@_end:

endef
export INCBIN

# default target
.PHONY: all
all: $(EXE) ## build executable

.PHONY: run
run: $(EXE) ## run program
	@./$(EXE)

.PHONY: debug
debug: CFLAGS := $(filter-out -O2,$(CFLAGS)) -D_DEBUG -g
debug: CXXFLAGS := $(filter-out -O2,$(CXXFLAGS)) -D_DEBUG -g
debug: LDFLAGS := $(filter-out -s,$(LDFLAGS))
debug: $(EXE) ## build with debug enabled

.PHONY: debugrun
debugrun: debug run ## run debug version

.PHONY: style
style: $(STYLED)

$(DEPDIR)/%.styled: $(SRCDIR)/%
	@$(COLOR)
	echo "Styling $(SRCDIR)/$*"
	@$(RESET)
	# sed is needed to fix string literals (uncrustify bug: https://github.com/uncrustify/uncrustify/issues/945)
	uncrustify -c .uncrustify.cfg --replace --no-backup $(SRCDIR)/$* && sed -i -e 's/\([uUL]\)\s\+\(['"'"'"]\)/\1\2/g' $(SRCDIR)/$* && touch $@

# link
$(EXE): $(OBJ)
	$(COLOR)
	echo "Link $^ -> $@"
	$(RESET)
	$(CC) -Wl,--as-needed -o $@ $(OBJ) $(LDFLAGS)

# create binary blobs for other files
$(filter-out %.c.o %.cpp.o,$(OBJ)): $(OBJDIR)/%.o: $(SRCDIR)/%
	@$(COLOR)
	echo "Other file $(SRCDIR)/$* -> $@"
	@$(RESET)
	echo "$$INCBIN" | sed -e 's/@sym@/$(subst .,_,$*)/' -e 's/@file@/$</' | gcc -x assembler-with-cpp - -c -o $@

# compile
$(OBJDIR)/%.c.o: $(DEPDIR)/%.c.d
	@$(COLOR)
	echo "Compile $(SRCDIR)/$*.c -> $@"
	@$(RESET)
	$(CC) $(CFLAGS) -c -o $@ $(SRCDIR)/$*.c

# compile
$(OBJDIR)/%.cpp.o: $(DEPDIR)/%.cpp.d
	@$(COLOR)
	echo "Compile $(SRCDIR)/$*.cpp -> $@"
	@$(RESET)
	$(CXX) $(CXXFLAGS) -c -o $@ $(SRCDIR)/$*.cpp

# build dependecies list
$(DEPDIR)/%.c.d: $(SRCDIR)/%.c
	@$(COLOR)
	echo "Generating dependencies $(SRCDIR)/$*.c -> $@"
	@$(RESET)
	$(CC) $(DEPFLAGS) -MM -MT '$$(OBJDIR)/$*.c.o' $< | sed 's,^\([^:]\+.o\):,\1 $$(DEPDIR)/$*.c.d:,' > $@
# $(CC) $(DEPFLAGS) -MM -MT '$$(OBJDIR)/$*.c.o' -MF $@ $<
# sed -i 's,^\([^:]\+.o\):,\1 $$(DEPDIR)/$*.c.d:,' $@

# build dependecies list
$(DEPDIR)/%.cpp.d: $(SRCDIR)/%.cpp
	@$(COLOR)
	echo "Generating dependencies $(SRCDIR)/$*.cpp -> $@"
	@$(RESET)
	$(CXX) $(DEPFLAGS) -MM -MT '$$(OBJDIR)/$*.cpp.o' $< | sed 's,^\([^:]\+.o\):,\1 $$(DEPDIR)/$*.cpp.d:,' > $@
# $(CXX) $(DEPFLAGS) -MM -MT '$$(OBJDIR)/$*.cpp.o' -MF $@ $<
# sed -i 's,^\([^:]\+.o\):,\1 $$(DEPDIR)/$*.cpp.d:,' $@

# include generated dependencies
-include $(wildcard $(DEP))

# depend on directory
$(OBJ): | $(OBJDIR)
$(DEP): | $(DEPDIR)
$(STYLED): | $(DEPDIR)

# create directory
$(OBJDIR):
	-$(MKDIR) $(OBJDIR)

# create directory
$(DEPDIR):
	-$(MKDIR) $(DEPDIR)

# delete stuff
.PHONY: clean
clean: mostlyclean ## delete everything this Makefile created
	-$(RM) $(EXE)

.PHONY: mostlyclean
mostlyclean: ## delete everything created, leave executable
	@$(COLOR)
	echo "Cleaning"
	@$(RESET)
ifneq ($(wildcard $(OBJDIR)),)
	-$(RM) $(OBJ)
	-$(RMDIR) $(OBJDIR)
endif
ifneq ($(wildcard $(DEPDIR)),)
	-$(RM) $(DEP)
	-$(RM) $(STYLED)
	-$(RMDIR) $(DEPDIR)
endif

.PHONY: forceclean
forceclean: ## force delete all created temporary folders
	@$(COLOR)
	echo "Force cleaning"
	@$(RESET)
ifneq ($(wildcard $(OBJDIR)),)
	-$(RM) -r $(OBJDIR)
endif
ifneq ($(wildcard $(DEPDIR)),)
	-$(RM) -r $(DEPDIR)
endif

.PHONY: help
help: ## show this help
	@awk -F':.*##' '/: [^#]*##/{ printf("%12s: %s\n", $$1, $$2)}' $(MAKEFILE_LIST)

