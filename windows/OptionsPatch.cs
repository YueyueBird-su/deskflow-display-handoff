using System;
using System.Runtime.InteropServices;
using System.Text;

public static class OptionsGesturePatch {
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_open_v2(byte[] p,out IntPtr db,int flags,IntPtr vfs);
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_close(IntPtr db);
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_busy_timeout(IntPtr db,int ms);
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_prepare_v2(IntPtr db,byte[] sql,int length,out IntPtr stmt,IntPtr tail);
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_bind_text(IntPtr stmt,int index,byte[] value,int length,IntPtr destroy);
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_step(IntPtr stmt);
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_finalize(IntPtr stmt);
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern IntPtr sqlite3_column_text(IntPtr stmt,int col);
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_column_bytes(IntPtr stmt,int col);
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_changes(IntPtr db);
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern IntPtr sqlite3_backup_init(IntPtr dest,byte[] destName,IntPtr source,byte[] sourceName);
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_backup_step(IntPtr backup,int pages);
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_backup_finish(IntPtr backup);

    static byte[] Utf8(string text){return Encoding.UTF8.GetBytes(text+"\0");}
    static IntPtr Open(string path,int flags){IntPtr db;int rc=sqlite3_open_v2(Utf8(path),out db,flags,IntPtr.Zero);if(rc!=0){if(db!=IntPtr.Zero)sqlite3_close(db);throw new InvalidOperationException("SQLite open result "+rc);}sqlite3_busy_timeout(db,3000);return db;}
    static IntPtr Prepare(IntPtr db,string sql,string[] values){
        IntPtr stmt;int rc=sqlite3_prepare_v2(db,Utf8(sql),-1,out stmt,IntPtr.Zero);
        if(rc!=0)throw new InvalidOperationException("SQLite prepare result "+rc);
        try{for(int i=0;i<values.Length;i++){byte[] bytes=Encoding.UTF8.GetBytes(values[i]);rc=sqlite3_bind_text(stmt,i+1,bytes,bytes.Length,new IntPtr(-1));if(rc!=0)throw new InvalidOperationException("SQLite bind result "+rc);}return stmt;}
        catch{sqlite3_finalize(stmt);throw;}
    }
    static void Execute(IntPtr db,string sql,params string[] values){IntPtr stmt=Prepare(db,sql,values);try{int rc=sqlite3_step(stmt);if(rc!=101)throw new InvalidOperationException("SQLite step result "+rc);}finally{sqlite3_finalize(stmt);}}
    static string Scalar(IntPtr db,string sql,params string[] values){
        IntPtr stmt=Prepare(db,sql,values);
        try{if(sqlite3_step(stmt)!=100)throw new InvalidOperationException("Expected a SQLite result row.");int len=sqlite3_column_bytes(stmt,0);byte[] b=new byte[len];if(len>0)Marshal.Copy(sqlite3_column_text(stmt,0),b,0,len);return Encoding.UTF8.GetString(b);}
        finally{sqlite3_finalize(stmt);}
    }
    public static void Backup(string path,string destination){
        IntPtr source=Open(path,1),dest=IntPtr.Zero,backup=IntPtr.Zero;
        try{dest=Open(destination,6);backup=sqlite3_backup_init(dest,Utf8("main"),source,Utf8("main"));if(backup==IntPtr.Zero)throw new InvalidOperationException("SQLite backup init failed.");int rc=sqlite3_backup_step(backup,-1);if(rc!=101)throw new InvalidOperationException("SQLite backup result "+rc);}
        finally{if(backup!=IntPtr.Zero)sqlite3_backup_finish(backup);if(dest!=IntPtr.Zero)sqlite3_close(dest);sqlite3_close(source);}
    }
    public static void Apply(string path,string cardPath,string newCustom){
        IntPtr db=Open(path,2);bool transaction=false;
        string selected=cardPath+".selectedNestedCard",custom=cardPath+".nestedCards.custom_gesture";
        try{
            Execute(db,"BEGIN IMMEDIATE");transaction=true;
            foreach(string direction in new string[]{"click","left","right","up","down"})
                if(Scalar(db,"SELECT json_extract(file,?1) FROM data ORDER BY _id DESC LIMIT 1",custom+".nestedCards."+direction+".macro.type")!="DO_NOTHING")
                    throw new InvalidOperationException("Existing custom gesture actions changed; rolling back.");
            string before=Scalar(db,"SELECT json_remove(CAST(file AS TEXT),?1,?2) FROM data ORDER BY _id DESC LIMIT 1",selected,custom);
            Execute(db,"UPDATE data SET file=CAST(json_set(CAST(file AS TEXT),?1,json(?2),?3,?4) AS BLOB) WHERE _id=(SELECT MAX(_id) FROM data) AND json_extract(file,?3)=?5 AND json_extract(file,?6)=?7",custom,newCustom,selected,"custom_gesture","virtual_desktops",cardPath+".id","card_global_presets_one_of_gesture_button");
            if(sqlite3_changes(db)!=1)throw new InvalidOperationException("Gesture precondition changed; nothing was committed.");
            string after=Scalar(db,"SELECT json_remove(CAST(file AS TEXT),?1,?2) FROM data ORDER BY _id DESC LIMIT 1",selected,custom);
            if(before!=after)throw new InvalidOperationException("An unrelated setting changed; rolling back.");
            Execute(db,"COMMIT");transaction=false;
        }finally{if(transaction){try{Execute(db,"ROLLBACK");}catch{}}sqlite3_close(db);}
    }
}
