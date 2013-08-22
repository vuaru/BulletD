module bullet.bindings.bindings;

import std.algorithm;
import std.conv;
import std.string;
public import std.traits;

public import bullet.bindings.util;

version(genBindings) {
	public import std.stdio;
}

version(Windows) {
	//Produces a workaround for OMF symbol length limitations
	version = adjustSymbols;
}

version(adjustSymbols) {
	version(genBindings) {} else {
		public import bullet.bindings.glue;
	}

	//Applies the 64-bit FNV-1a hash function to a string
	ulong fnv1a(string str) pure {
		ulong hash = 14695981039346656037u;
		foreach(char c; str) {
			hash ^= cast(ulong)c;
			hash *= 1099511628211;
		}
		return hash;
	}

	template symbolName(Class, string name, ArgTypes ...) {
		enum symbolName = "_glue_" ~ fnv1a(Class.stringof ~ " " ~ name ~ "(" ~ argList!(dType, 0, ArgTypes) ~ ")").to!string();
	}
}

public import bullet.bindings.types;

mixin template basicClassBinding(string _cppName) {
	enum string cppName = _cppName; 

	version(genBindings) {
		import std.stdio;

		static void writeBindings(File f) {
			bindingClasses ~= cppName;

			foreach(member; __traits(allMembers, typeof(this))) {
				//TODO: remove the check for double-underscore identifiers once the related bug is fixed?
				static if(member.length <= 2 || member[0 .. 2] != "__") {
					//TODO: handle issue with conflicts between members of mixins.
					foreach(attribute; __traits(getAttributes, __traits(getMember, typeof(this), member))) {
						static if(is(attribute == Binding)) {
							static if(member.length > 8 && member[0 .. 8] == "_d_glue_") {
								dGlueFunctions ~= __traits(getMember, typeof(this), member);
							}
							static if(member.length > 9 && member[0 .. 9] == "_binding_") {
								f.writeln(__traits(getMember, typeof(this), member));
							}
						}
					}
				}
			}
		}
	}
}

/++
Makes a struct into a binding to a C++ class
+/
mixin template classBinding(string _cppName) {
	mixin basicClassBinding!(_cppName);

	mixin destructor;

	//To do: prevent access to superclass constructors?

	private:
	ubyte[cppSize!(cppName)] _this;
}

mixin template subclassBinding(string _cppName, Super) {
	mixin basicClassBinding!(_cppName);
	Super _super;
	alias _super this;

	private:
	ubyte[cppSize!(cppName) - cppSize!(Super.cppName)] _extra;
}

enum Binding;

/++
Creates a binding to a C++ method
+/
mixin template method(T, string name, ArgTypes ...) {
	mixin(dMethod!(typeof(this), "", T, name, ArgTypes));
	version(genBindings) {
		mixin(cMethod!(typeof(this), cMethodBinding, T, name, ArgTypes));
	}
}

/++
Creates a binding to a C++ constructor

The constructor is faked using a static opCall().
+/
mixin template constructor(ArgTypes ...) {
	mixin(dMethod!(typeof(this), "static", typeof(this), "opCall", ArgTypes));
	//TODO: unify opNew with this mixin template?
	mixin opNew!(ArgTypes);
	version(genBindings) {
		mixin(cMethod!(typeof(this), cConstructorBinding, typeof(this), "opCall", ArgTypes));
	}
}

/++
Creates a binding to the C++ "new" operator
+/
mixin template opNew(ArgTypes ...) {
	mixin(dMethod!(typeof(this), "static", typeof(this)*, "cppNew", ArgTypes));
	version(genBindings) {
		mixin(cMethod!(typeof(this), cNewBinding, typeof(this)*, "cppNew", ArgTypes));
	}
}

/++
Creates a binding to the C++ destructor

Automatically mixed in by classBinding
+/
mixin template destructor() {
	//To do: rename destroy()?
	mixin(dMethod!(typeof(this), "private", void, "_destroy"));
	mixin(dMethod!(typeof(this), "", void, "cppDelete"));
	version(genBindings) {
		mixin(cMethod!(typeof(this), cDestructorBinding, void, "_destroy"));
		mixin(cMethod!(typeof(this), cDeleteBinding, void, "cppDelete"));
		~this() {}
	} else {
		~this() {
			_destroy();
		}
	}
}

/++
Converts ArgTypes to a comma-separated argument string, using the template transform to map the types to strings
+/
template argList(alias transform, size_t start, ArgTypes ...) {
	static if(ArgTypes.length == 0) {
		enum argList = "";
	} else static if(ArgTypes.length == 1) {
		private alias transformed = transform!(ArgTypes[0]);
		enum argList = transformed ~ " a" ~ start.to!string();
	} else {
		enum argList = argList!(transform, start, ArgTypes[0]) ~ ", " ~ argList!(transform, start + 1, ArgTypes[1 .. $]);
	}
}

/++
Produces a string containing argument names of the form "ai", where i is in the range [0, n), separated by commas
+/
template argNames(size_t n) {
	static if(n == 0) {
		enum argNames = "";
	} else static if(n == 1) {
		enum argNames = "a" ~ (n - 1).to!string();
	} else {
		enum argNames = argNames!(n - 1) ~ ", a" ~ (n - 1).to!string();
	}
}

/++
Produces mixin text for the beginning of a D declaration/definition

Designed for internal convenience
+/
template dMethodCommon(string qualifiers, T, string name, ArgTypes ...) {
	enum dMethodCommon = qualifiers ~ " " ~ dType!T ~ " " ~ name ~ "(" ~ argList!(dType, 0, ArgTypes) ~ ")";
}

/++
Produces mixin text for the D side of a method/constructor/etc. binding
+/
template dMethod(Class, string qualifiers, T, string name, ArgTypes ...) {
	private enum common = dMethodCommon!(qualifiers, T, name, ArgTypes);
	version(adjustSymbols) {
		private enum isStatic = qualifiers.split.canFind("static");
		version(genBindings) {
			private enum symName = symbolName!(Class, name, ArgTypes);
			enum dMethod = common ~ ";" ~
				"@Binding immutable string _d_glue_" ~ symName ~ " = `" ~ dGlue!(Class, T, symName, isStatic, ArgTypes) ~ "`;";
		} else {
			enum dMethod = common ~ " {" ~
				"return " ~ symbolName!(Class, name, ArgTypes) ~ "(" ~
				(isStatic ? "" : "this" ~ (ArgTypes.length ? ", " : "")) ~ argNames!(ArgTypes.length) ~ ");" ~
				"}";
		}
	} else {
		enum dMethod = "extern(C) " ~ common ~ ";";
	}
}

version(adjustSymbols) {
	template dGlue(Class, T, string symName, bool isStatic, ArgTypes ...) {
		static if(isStatic) {
			private enum common = dMethodCommon!("extern(C)", T, symName, ArgTypes);
		} else {
			private enum common = dMethodCommon!("extern(C)", T, symName, RefParam!Class, ArgTypes);
		}
		enum dGlue = common ~ ";";
	}
}

/++
Produces text for the generation of C-side glue functions
+/
template cMethod(Class, alias generator, T, string name, ArgTypes ...) {
	version(adjustSymbols) {
		private enum symName = symbolName!(Class, name, ArgTypes);
	} else {
		private enum symName = __traits(getMember, Class, name).mangleof;
	}
	private enum generated = generator!(Class, T, name, symName, ArgTypes);
	enum cMethod = "@Binding immutable string _binding_" ~ symName ~ " = `" ~ generated ~ "`;"; 
}

version(genBindings) {
	template cMethodBinding(Class, T, string name, string symName, ArgTypes ...) {
		enum cMethodBinding = `extern "C" ` ~ cppType!T ~ " " ~ symName ~ "(" ~ Class.cppName ~ "* _this" ~ (ArgTypes.length ? ", " : "") ~ argList!(cppType, 0, ArgTypes) ~ ") {\n" ~
			"\treturn _this->" ~ name ~ "(" ~ argNames!(ArgTypes.length) ~ "); \n" ~
		"}\n";
	}

	template cConstructorBinding(Class, T: Class, string name: "opCall", string symName, ArgTypes ...) {
		enum cConstructorBinding = `extern "C" ` ~ Class.cppName ~ " " ~ symName ~ "(" ~ argList!(cppType, 0, ArgTypes) ~ ") {\n" ~
			"\treturn " ~ Class.cppName ~ "(" ~ argNames!(ArgTypes.length) ~ ");\n" ~
			"}\n";
	}

	//Currently unused due to issues with aliasing constructors from different mixins
	template cConstructorBinding(Class, T: void, string name: "_construct", string symName, ArgTypes ...) {
		enum cConstructorBinding = `extern "C" void ` ~ symName ~ "(" ~ Class.cppName ~ "* _this" ~ (ArgTypes.length ? ", " : "") ~ argList!(cppType, 0, ArgTypes) ~ ") {\n" ~
			"\tnew(_this) " ~ Class.cppName ~ "(" ~ argNames!(ArgTypes.length) ~ ");\n" ~
			"}\n";
	}

	//To do: array new/delete?
	template cNewBinding(Class, T, string name, string symName, ArgTypes ...) {
		enum cNewBinding = `extern "C" ` ~ Class.cppName ~ "* " ~ symName ~ "(" ~ argList!(cppType, 0, ArgTypes) ~ ") {\n" ~
			"\treturn new " ~ Class.cppName ~ "(" ~ argNames!(ArgTypes.length) ~ ");\n" ~
			"}\n";
	}

	template cDestructorBinding(Class, T, string name, string symName) {
		enum cDestructorBinding = `extern "C" void ` ~ symName ~ "(" ~ Class.cppName ~ "* _this) {\n" ~
			"\t_this->~" ~ Class.cppName ~ "();\n" ~
			"}\n";
	}
	
	template cDeleteBinding(Class, T, string name, string symName) {
		enum cDeleteBinding = `extern "C" void ` ~ symName ~ "(" ~ Class.cppName ~ "* _this) {\n" ~
			"\tdelete _this;\n" ~
			"}\n";
	}

	//Nasty, icky global variables used for binding generation
	//To do: convert to sets?
	string[] bindingIncludes;
	string[] bindingClasses;

	version(adjustSymbols) {
		string[] dGlueFunctions;

		void writeDGlue() {
			auto f = File("bullet/bindings/glue.d", "w");
			
			f.write("module bullet.bindings.glue;\n\nimport bullet.all;\n\n");

			foreach(fn; dGlueFunctions) {
				f.writeln(fn);
			}
		}
	} else {
		//Dummied out for convenience
		void writeDGlue() {}
	}

	void writeIncludes(File f, string[] includes ...) {
		f.writeln("#include <new>");
		foreach(s; includes) {
			f.writeln(s);
			bindingIncludes ~= s;
		}
	}

	void writeGenC() {
		auto f = File("gen_c.cpp", "w");
		f.writeln("#include <fstream>");
		foreach(s; bindingIncludes) {
			f.writeln(s);
		}
		f.writeln(`
using namespace std;
int main(int argc, char** argv) {
	ofstream f;
	f.open("bullet/bindings/sizes.d");

	f << "module bullet.bindings.sizes;\n\n";
	`);
		foreach(cppName; bindingClasses) {
			//To do: escape quotes in cppName?
			f.writeln("\t", "f << \"template cppSize(string cppName: `", cppName, "`) {\\n\";");
			f.writeln("\t", `f << "\tenum size_t cppSize = " << sizeof(` ~ cppName ~ `) << ";\n";`);
			f.writeln("\t", `f << "}\n" << endl;`);
		}
		f.writeln("}");
	}
}


