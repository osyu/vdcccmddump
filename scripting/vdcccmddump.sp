#pragma newdecls required
#pragma semicolon 1

#define PLUGIN_VERSION "1.0.2"

#define NAME_SIZE 256
#define DESC_SIZE 1024

public Plugin myinfo =
{
  name = "VDC CCmd Dump",
  author = "osyu",
  description = "Dump CCmds and CVars in wikitext table format",
  version = PLUGIN_VERSION,
  url = "https://osyu.sh/"
};

enum struct SCCmd
{
  char name[NAME_SIZE];
  bool iscmd;
  int flags;
  char desc[DESC_SIZE];
}

char p_flags[][] = {
  "unregistered", "devonly", "game", "client",
  "hidden", "protected", "singleplayer", "archive",
  "notify", "userinfo", "printonly", "unlogged",
  "neverprint", "replicated", "cheat", "",
  "demo", "norecord", "", "",
  "reloadmat", "reloadtex", "notconnected", "matsysthread",
  "archivexbox", "accessible_from_threads", "", "",
  "svcanexec", "svcannotquery", "clcmdcanexec"
};


public void OnPluginStart()
{
  RegServerCmd("sm_dump_ccmds", dump, "Dump all ConCommands and ConVars into a text file in wikitext table format");
}


Action dump(int args)
{
  char appid[16];
  char version[16];
  GetSteamInfValue("appID", appid, sizeof(appid));
  GetSteamInfValue("PatchVersion", version, sizeof(appid));

  char path[PLATFORM_MAX_PATH];
  BuildPath(Path_SM, path, sizeof(path), "data/ccmd_dump_%s_%s.txt", appid, version);

  PrintToServer("dumping into %s", path);

  File fh_dump = OpenFile(path, "w", false, NULL_STRING);

  if (fh_dump == null)
  {
    PrintToServer("failed to open file");
    return;
  }

  ArrayList a_ccmds = new ArrayList(sizeof(SCCmd), 0);

  SCCmd ccmd;
  Handle h_ccmditer = FindFirstConCommand(ccmd.name, sizeof(ccmd.name), ccmd.iscmd, ccmd.flags, ccmd.desc, sizeof(ccmd.desc));

  if (h_ccmditer == null)
  {
    fh_dump.Close();
    PrintToServer("failed to fetch ccmds");
    return;
  }

  if (!IsAddonCCmd(ccmd.name))
  {
    a_ccmds.PushArray(ccmd);
  }

  while (FindNextConCommand(h_ccmditer, ccmd.name, sizeof(ccmd.name), ccmd.iscmd, ccmd.flags, ccmd.desc, sizeof(ccmd.desc)))
  {
    if (!IsAddonCCmd(ccmd.name))
    {
      a_ccmds.PushArray(ccmd);
    }
  }
  h_ccmditer.Close();

  a_ccmds.SortCustom(SortCCmd);

  WriteDumpWikiTable(fh_dump, a_ccmds, version);

  a_ccmds.Close();
  fh_dump.Close();
}


// GLHF!
void WriteDumpWikiTable(File fh, ArrayList arr, char[] version)
{
  fh.WriteLine("<!-- build number: %s, total ccmds: %d -->", version, arr.Length);

  fh.WriteString("{|class=\"standard-table\" style=\"margin:1em 0;width:100%;white-space:pre-wrap\"\n"
            ... "! Name !! Cmd? !! Default !! Min !! Max !! Flags !! Description\n", false);

  char alphchar;
  char namestrp[NAME_SIZE];
  char style[64];
  char defvalue[256];
  float _min, _max;
  char min[16], max[16];
  char ftchar;
  bool write_delim;
  SCCmd buf;

  for (int i = 0; i < arr.Length; i++)
  {
    arr.GetArray(i, buf);

    strcopy(namestrp, sizeof(namestrp), buf.name);
    StripCCmdName(namestrp, sizeof(namestrp));

    if (!(~buf.flags & (1<<1 | 1<<14))) // DEVONLY+CHEAT
      style = ";color:#5a5151;font-style:italic";
    else if (buf.flags & 1<<1) // DEVONLY
      style = ";color:#515151;font-style:italic";
    else if (!(~buf.flags & (1<<4 | 1<<14))) // HIDDEN+CHEAT
      style = ";color:#8f7877";
    else if (buf.flags & 1<<4) // HIDDEN
      style = ";color:#797877";
    else if (buf.flags & 1<<14) // CHEAT
      style = ";color:#e4b7b5";
    else // NORMAL
      style[0] = 0;

    if (!buf.iscmd)
    {
      ConVar cvar = FindConVar(buf.name);

      cvar.GetDefault(defvalue, sizeof(defvalue));
      if (defvalue[0])
      {
        ReplaceString(defvalue, sizeof(defvalue), "://", "<nowiki>://</nowiki>");
        ReplaceString(defvalue, sizeof(defvalue), "|", "<nowiki>|</nowiki>");
      }

      if (cvar.GetBounds(ConVarBound_Lower, _min))
      {
        FloatToString(_min, min, sizeof(min));
        FloatPrettyFmt(min);
      }
      else
      {
        min[0] = 0;
      }

      if (cvar.GetBounds(ConVarBound_Upper, _max))
      {
        FloatToString(_max, max, sizeof(max));
        FloatPrettyFmt(max);
      }
      else
      {
        max[0] = 0;
      }

      cvar.Close();
    }
    else
    {
      defvalue[0] = 0;
      min[0] = 0;
      max[0] = 0;
    }

    if (buf.desc[0])
    {
      TrimString(buf.desc);

      ReplaceString(buf.desc, sizeof(buf.desc), "\n", "<br>");
      ReplaceString(buf.desc, sizeof(buf.desc), "://", "<nowiki>://</nowiki>");
      ReplaceString(buf.desc, sizeof(buf.desc), "|", "<nowiki>|</nowiki>");
    }

    // row start
    fh.WriteString("|-", false);
    if (CharToUpper(namestrp[0]) != alphchar)
    {
      alphchar = CharToUpper(namestrp[0]);
      fh.WriteString("id=\"", false);
      fh.WriteInt8(alphchar);
      fh.WriteString("\" ", false);
    }
    fh.WriteString("style=\"vertical-align:top", false);
    fh.WriteString(style, false);
    fh.WriteString("\"\n", false);

    // name
    fh.WriteInt8('|');
    ftchar = buf.name[0];
    if (ftchar == '+' || ftchar == '-')
    {
      fh.WriteInt8('|');
    }
    fh.WriteString(buf.name, false);

    // cmd?
    fh.WriteString("||", false);
    if (buf.iscmd)
    {
      fh.WriteString("style=\"text-align:center\"|cmd", false);
    }

    // default
    fh.WriteString("||", false);
    if (defvalue[0])
    {
      fh.WriteString("style=\"word-break:break-all\"|", false);
      fh.WriteString(defvalue, false);
    }

    // min
    fh.WriteString("||", false);
    fh.WriteString(min, false);

    // max
    fh.WriteString("||", false);
    fh.WriteString(max, false);

    // flags
    fh.WriteString("||", false);
    write_delim = false;
    for (int j = 0; j < sizeof(p_flags); j++)
    {
      if (buf.flags & 1 << j && p_flags[j][0])
      {
        if (write_delim)
        {
          fh.WriteInt8(' ');
        }
        fh.WriteString(p_flags[j], false);
        write_delim = true;
      }
    }

    // description
    fh.WriteString("||", false);
    fh.WriteString(buf.desc, false);

    fh.WriteString("\n", false);
  }

  fh.WriteString("|}\n", false);
}


int SortCCmd(int idx1, int idx2, Handle arr, Handle hndl)
{
  SCCmd buf1;
  SCCmd buf2;
  GetArrayArray(arr, idx1, buf1);
  GetArrayArray(arr, idx2, buf2);
  StripCCmdName(buf1.name, sizeof(buf1.name));
  StripCCmdName(buf2.name, sizeof(buf2.name));

  return strcmp(buf1.name, buf2.name, false);
}


void StripCCmdName(char[] name, int maxlength)
{
  char v = name[0];

  if (v == '+' || v == '-')
  {
    int len = strcopy(name, maxlength - 1, name[1]);
    name[len] = v;
    name[len + 1] = 0;
  }
}


void FloatPrettyFmt(char[] s_float)
{
  for (int i = strlen(s_float) - 1; i >= 0; i--)
  {
    if (s_float[i] == '0')
    {
      s_float[i] = 0;
    }
    else
    {
      break;
    }
  }

  if (s_float[strlen(s_float) - 1] == '.')
  {
    s_float[strlen(s_float) - 1] = 0;
  }
}


bool IsAddonCCmd(char[] name)
{
  if (StrEqual(name, "metamod_version") ||
      StrEqual(name, "sourcemod_version") ||
      StrEqual(name, "mm") ||
      StrEqual(name, "sm") ||
      StrContains(name, "mm_") == 0 ||
      StrContains(name, "sm_") == 0 ||
      StrContains(name, "prec_") == 0)
  {
    return true;
  }

  return false;
}


int GetSteamInfValue(const char[] key, char[] buffer, int maxlength)
{
  File fh_sinf = OpenFile("steam.inf", "r", false, NULL_STRING);
  char value[64];
  char line[64];

  char keym[64];
  strcopy(keym, sizeof(keym), key);
  keym[strlen(keym)] = '=';

  do
  {
    if (!fh_sinf.ReadLine(line, sizeof(line)))
    {
      fh_sinf.Close();
      return false;
    }
  }
  while (StrContains(line, keym) != 0);

  fh_sinf.Close();

  StrCat(value, sizeof(value), line[FindCharInString(line, '=') + 1]);
  TrimString(value);

  strcopy(buffer, maxlength, value);
  return true;
}
