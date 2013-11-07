module bullet.bindings.dmethods;

import bullet.bindings.bindings;

enum Binding;

/*
called by dMethod:
	void _destroy()

called by dGlue:
	extern(C) void _glue_12203819563545677224(ref btTypedObject a0)
*/
template dMethodCommon(string qualifiers, T, string name, ArgTypes ...)
{
	enum dMethodCommon = qualifiers ~ " " ~ dType!T ~ " " ~ name ~ "(" ~ argList!(dType, 0, ArgTypes) ~ ")";
}

template dMethod(Class, string qualifiers, T, string name, ArgTypes ...)
{
	private enum common = dMethodCommon!(qualifiers, T, name, ArgTypes);

	static if(adjustSymbols)
	{
		import std.string: split, canFind;

		private enum isStatic = qualifiers.split.canFind("static");

		private enum symName = symbolName!(Class, name, ArgTypes);

		/*
			void _destroy();
			@Binding immutable string _d_glue__glue_12203819563545677224 = `extern(C) void _glue_12203819563545677224(ref btTypedObject a0);`;
		*/
		static if(bindSymbols)
		{
			private enum glueExtern = dGlueDefineExtern!(Class, T, symName, isStatic, ArgTypes);

			enum dMethod = common ~ ";" ~
				"@Binding immutable string _d_glue_" ~ symName ~ " = `" ~ glueExtern ~ "`;";
		}
		/*
 			void _destroy() {return _glue_12203819563545677224(this);}
		*/
		else
		{
			enum glueCallExtern = dGlueCallExtern!(isStatic, ArgTypes);

			enum dMethod = common ~ " {" ~
				"return " ~ symName ~ "(" ~	glueCallExtern ~ ");" ~
				"}";
		}
	}
	else
	{
		enum dMethod = "extern(C) " ~ common ~ ";";
	}
}

static if(adjustSymbols)
{
	/*
		extern(C) void _glue_12203819563545677224(ref btTypedObject a0);
	*/
	template dGlueDefineExtern(Class, T, string symName, bool isStatic, ArgTypes ...)
	{
		static if(isStatic)
			enum dGlueDefineExtern = dMethodCommon!("extern(C)", T, symName,                 ArgTypes) ~ ";";
		else
			enum dGlueDefineExtern = dMethodCommon!("extern(C)", T, symName, RefParam!Class, ArgTypes) ~ ";";
	}

	/*
		this, a0
	*/
	template dGlueCallExtern(bool isStatic, ArgTypes ...)
	{
		static if(isStatic)
			enum dGlueCallExtern = argNames!(ArgTypes.length);
		else
			enum dGlueCallExtern = "this" ~ (ArgTypes.length ? ", " : "") ~ argNames!(ArgTypes.length);
	}
}


mixin template method(T, string name, ArgTypes ...)
{
	mixin(dMethod!(typeof(this), "", T, name, ArgTypes));

	static if(bindSymbols)
		mixin(cMethod!(typeof(this), cMethodBinding, T, name, ArgTypes));
}