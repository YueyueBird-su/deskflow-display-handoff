using System;
using System.Runtime.InteropServices;
using System.Text;

public static class OptionsReadOnly {
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)]
    static extern int sqlite3_open_v2(byte[] path, out IntPtr database, int flags, IntPtr vfs);
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)]
    static extern int sqlite3_close(IntPtr database);
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)]
    static extern int sqlite3_busy_timeout(IntPtr database, int milliseconds);
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)]
    static extern int sqlite3_prepare_v2(IntPtr database, byte[] sql, int length, out IntPtr statement, IntPtr tail);
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)]
    static extern int sqlite3_step(IntPtr statement);
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)]
    static extern IntPtr sqlite3_column_blob(IntPtr statement, int column);
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)]
    static extern int sqlite3_column_bytes(IntPtr statement, int column);
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)]
    static extern int sqlite3_finalize(IntPtr statement);

    public static string Read(string path) {
        IntPtr database=IntPtr.Zero, statement=IntPtr.Zero;
        try {
            int result=sqlite3_open_v2(Encoding.UTF8.GetBytes(path+"\0"),out database,1,IntPtr.Zero);
            if(result!=0)throw new InvalidOperationException("Read-only database open returned "+result);
            sqlite3_busy_timeout(database,2500);
            byte[] sql=Encoding.UTF8.GetBytes("SELECT file FROM data ORDER BY _id DESC LIMIT 1\0");
            result=sqlite3_prepare_v2(database,sql,-1,out statement,IntPtr.Zero);
            if(result!=0)throw new InvalidOperationException("Read-only statement returned "+result);
            if(sqlite3_step(statement)!=100)throw new InvalidOperationException("No settings row was found.");
            int length=sqlite3_column_bytes(statement,0);
            byte[] bytes=new byte[length];
            Marshal.Copy(sqlite3_column_blob(statement,0),bytes,0,length);
            return Encoding.UTF8.GetString(bytes);
        } finally {
            if(statement!=IntPtr.Zero)sqlite3_finalize(statement);
            if(database!=IntPtr.Zero)sqlite3_close(database);
        }
    }
}
