# Draws ADAM's artwork from the title's boing ball and four Amiga stripes:
#   options/windows/icons/icon.ico   app icon (16-256 px)
#   promo/itch_cover.png             itch.io cover, 630 x 500
# Usage:  powershell -File tools\make_art.ps1 [-Png icon256.png]   (-Png also saves the 256px icon)
param(
    [string]$Png = ""
)
$root = Split-Path -Parent $PSScriptRoot
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @"
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Drawing.Text;
using System.IO;

public static class AdamArt
{
    // colours from the title (scr_ws_shell draw_logo, scr_machine draw_boing)
    static readonly double[][] Stripes = {
        new double[] {230, 60, 50}, new double[] {250, 160, 40},
        new double[] {90, 190, 90}, new double[] {60, 130, 230} };

    static void Mix(double[] c, double r, double g, double b, double k)
    {
        c[0] += (r - c[0]) * k; c[1] += (g - c[1]) * k; c[2] += (b - c[2]) * k;
    }

    // soft shadow under a ball at (cx, cy, r), offset (ox, oy)
    static void BallShadow(double[] c, double u, double v, double cx, double cy, double r, double ox, double oy, double k)
    {
        double sd = Math.Sqrt((u - cx - ox) * (u - cx - ox) + (v - cy - oy) * (v - cy - oy));
        double soft = r * 0.1;
        if (sd < r + soft) { Mix(c, 0, 0, 0, k * Math.Min(1, (r + soft - sd) / (2 * soft))); }
    }

    // the checked boing ball (tilted 20 degrees, lit from the top left); false if (u, v) misses it
    static bool Ball(double[] c, double u, double v, double cx, double cy, double r)
    {
        double nx = (u - cx) / r, ny = (v - cy) / r, d = nx * nx + ny * ny;
        if (d > 1) { return false; }
        double nz = Math.Sqrt(1 - d);
        double a = 20 * Math.PI / 180;
        double tx = nx * Math.Cos(a) - ny * Math.Sin(a);
        double ty = nx * Math.Sin(a) + ny * Math.Cos(a);
        double lon = Math.Atan2(tx, nz), lat = Math.Asin(Math.Max(-1, Math.Min(1, ty)));
        int cu = (int)Math.Floor((lon + Math.PI) / (Math.PI / 4));
        int cv = (int)Math.Floor((lat + Math.PI / 2) / (Math.PI / 8));
        double br, bg, bb;
        if (((cu + cv) & 1) == 0) { br = 225; bg = 30; bb = 40; } else { br = 255; bg = 255; bb = 255; }
        double dif = Math.Max(0, nx * -0.45 + ny * -0.55 + nz * 0.70);
        double sh = 0.50 + 0.55 * dif;
        c[0] = Math.Min(1, br * sh / 255); c[1] = Math.Min(1, bg * sh / 255); c[2] = Math.Min(1, bb * sh / 255); c[3] = 1;
        double hx = nx + 0.38, hy = ny + 0.42;
        double hl = Math.Max(0, 1 - Math.Sqrt(hx * hx + hy * hy) / 0.32);
        Mix(c, 1, 1, 1, 0.55 * hl * hl);
        return true;
    }

    // stripe i (0-3) colour into c if (u, v) is on a stripe leaning right
    static void Stripe(double[] c, double u, double v, double left, double top, double bottom, double sw, double gap, double lean, double bright)
    {
        if (v > bottom || v < top) { return; }
        for (int i = 0; i < 4; i++)
        {
            double x0 = left + i * gap + (bottom - v) * lean;
            if (u >= x0 && u < x0 + sw)
            {
                double[] s = Stripes[i];
                double k = 1.0 + bright * (bottom - v) / (bottom - top);
                c[0] = Math.Min(1, s[0] * k / 255); c[1] = Math.Min(1, s[1] * k / 255); c[2] = Math.Min(1, s[2] * k / 255); c[3] = 1;
            }
        }
    }

    // ---------- icon (256-unit space) ----------
    static double[] IconSample(double u, double v)
    {
        double[] c = { 0, 0, 0, 0 };
        double m = 6, rad = 52;
        double qx = Math.Max(Math.Abs(u - 128) - (128 - m - rad), 0);
        double qy = Math.Max(Math.Abs(v - 128) - (128 - m - rad), 0);
        if (Math.Sqrt(qx * qx + qy * qy) > rad) { return c; }
        double t = (v - m) / (256 - 2 * m);
        c[0] = (68 + (38 - 68) * t) / 255; c[1] = (79 + (45 - 79) * t) / 255; c[2] = (96 + (57 - 96) * t) / 255; c[3] = 1;
        if (v < 110) { Mix(c, 1, 1, 1, 0.05); }                    // top sheen, as on the badge
        Stripe(c, u, v, 112, -100, 222, 23, 31, 0.42, 0.12);       // running off the top edge
        BallShadow(c, u, v, 100, 150, 80, 10, 12, 0.45);
        Ball(c, u, v, 100, 150, 80);
        return c;
    }

    // ---------- itch.io cover (630 x 500) ----------
    const double Horizon = 340;
    const double CBx = 495, CBy = 222, CBr = 120;                  // the cover's ball

    // sky, floor and the ball's shadow (the title goes on top, then the ball)
    static double[] CoverBack(double u, double v)
    {
        double[] c = { 0, 0, 0, 1 };
        // sky: copper-style bands of whole colours, deep blue to purple
        double t = Math.Min(1, v / Horizon);
        double band = Math.Floor(t * 14) / 14;
        c[0] = (14 + 70 * band) / 255; c[1] = (18 + 16 * band) / 255; c[2] = (48 + 70 * band) / 255;
        if (v >= Horizon)
        {
            // floor: the Boing demo's purple grid in perspective
            double dv = v - Horizon + 0.5;
            double fz = (v - Horizon) / (500 - Horizon);
            c[0] = (34 + 26 * fz) / 255; c[1] = (22 + 12 * fz) / 255; c[2] = (56 + 30 * fz) / 255;
            double gx = (u - 315) * 2.2 / dv, gz = 900 / dv;
            double ppx = dv / 2.2, ppz = dv * dv / 900;             // pixels per grid square
            double ex = Math.Abs(gx - Math.Round(gx)) * ppx, ez = Math.Abs(gz - Math.Round(gz)) * ppz;
            double line = 0;
            if (ex < 1.1) { line = Math.Min(1, ppx / 4); }
            if (ez < 1.1) { line = Math.Max(line, Math.Min(1, (ppz - 1.5) / 5)); }
            if (line > 0) { Mix(c, 175 / 255.0, 95 / 255.0, 235 / 255.0, 0.9 * line); }
            if (v < Horizon + 1.5) { Mix(c, 1, 0.75, 0.95, 0.6); }  // horizon line
        }
        double sx = (u - CBx - 30) / 125, sy = (v - 432) / 20;      // floor shadow
        double e = sx * sx + sy * sy;
        if (e < 1) { Mix(c, 0, 0, 0, 0.6 * (1 - e)); }
        return c;
    }

    static double[] CoverBall(double u, double v)
    {
        double[] c = { 0, 0, 0, 0 };
        Ball(c, u, v, CBx, CBy, CBr);
        return c;
    }

    static Bitmap Render(int w, int h, double scale, Func<double, double, double[]> f, int ss)
    {
        var bmp = new Bitmap(w, h, PixelFormat.Format32bppArgb);
        for (int py = 0; py < h; py++)
        {
            for (int px = 0; px < w; px++)
            {
                double r = 0, g = 0, b = 0, a = 0;
                for (int sy = 0; sy < ss; sy++)
                {
                    for (int sx = 0; sx < ss; sx++)
                    {
                        double[] c = f((px + (sx + 0.5) / ss) * scale, (py + (sy + 0.5) / ss) * scale);
                        r += c[0] * c[3]; g += c[1] * c[3]; b += c[2] * c[3]; a += c[3];
                    }
                }
                if (a <= 0) { bmp.SetPixel(px, py, Color.FromArgb(0, 0, 0, 0)); continue; }
                bmp.SetPixel(px, py, Color.FromArgb(
                    (int)Math.Round(255 * a / (ss * ss)),
                    (int)Math.Round(255 * r / a), (int)Math.Round(255 * g / a), (int)Math.Round(255 * b / a)));
            }
        }
        return bmp;
    }

    // .ico with a PNG image per size (Windows Vista and later)
    public static void WriteIco(string path, int[] sizes, string png256)
    {
        var pngs = new byte[sizes.Length][];
        for (int i = 0; i < sizes.Length; i++)
        {
            using (var bmp = Render(sizes[i], sizes[i], 256.0 / sizes[i], IconSample, 6))
            using (var ms = new MemoryStream())
            {
                bmp.Save(ms, ImageFormat.Png);
                pngs[i] = ms.ToArray();
                if (sizes[i] == 256 && png256 != "") { File.WriteAllBytes(png256, pngs[i]); }
            }
        }
        using (var w = new BinaryWriter(File.Create(path)))
        {
            w.Write((ushort)0); w.Write((ushort)1); w.Write((ushort)sizes.Length);
            int off = 6 + 16 * sizes.Length;
            for (int i = 0; i < sizes.Length; i++)
            {
                w.Write((byte)(sizes[i] >= 256 ? 0 : sizes[i]));
                w.Write((byte)(sizes[i] >= 256 ? 0 : sizes[i]));
                w.Write((byte)0); w.Write((byte)0);
                w.Write((ushort)1); w.Write((ushort)32);
                w.Write((uint)pngs[i].Length); w.Write((uint)off);
                off += pngs[i].Length;
            }
            foreach (var p in pngs) { w.Write(p); }
        }
    }

    public static void WriteCover(string path, string fontDir)
    {
        using (var bmp = Render(630, 500, 1.0, CoverBack, 4))
        using (var ball = Render(630, 500, 1.0, CoverBall, 4))
        using (var g = Graphics.FromImage(bmp))
        using (var fonts = new PrivateFontCollection())
        {
            fonts.AddFontFile(Path.Combine(fontDir, "Poppins-Bold.ttf"));
            fonts.AddFontFile(Path.Combine(fontDir, "Poppins-Medium.ttf"));
            FontFamily pop = fonts.Families[0];
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
            g.PixelOffsetMode = PixelOffsetMode.HighQuality;

            // ADAM + stripes
            var title = new GraphicsPath();
            title.AddString("ADAM", pop, (int)FontStyle.Bold, 104, new PointF(30, 56), StringFormat.GenericTypographic);
            using (var shadow = (GraphicsPath)title.Clone())
            {
                var mtx = new Matrix(); mtx.Translate(5, 7); shadow.Transform(mtx);
                g.FillPath(new SolidBrush(Color.FromArgb(120, 0, 0, 0)), shadow);
            }
            g.FillPath(new LinearGradientBrush(new PointF(0, 60), new PointF(0, 170), Color.White, Color.FromArgb(205, 212, 232)), title);
            RectangleF tb = title.GetBounds();
            int[][] sc = { new[] {230, 60, 50}, new[] {250, 160, 40}, new[] {90, 190, 90}, new[] {60, 130, 230} };
            float sx = tb.Right + 16, sb = tb.Bottom, st = tb.Top + 4, sw = 11, lean = (sb - st) * 0.42f;
            for (int i = 0; i < 4; i++)
            {
                float o = sx + i * 15;
                g.FillPolygon(new SolidBrush(Color.FromArgb(sc[i][0], sc[i][1], sc[i][2])),
                    new[] { new PointF(o, sb), new PointF(o + sw, sb), new PointF(o + sw + lean, st), new PointF(o + lean, st) });
            }

            // taglines
            var orange = new SolidBrush(Color.FromArgb(255, 150, 40));
            var dim = new SolidBrush(Color.FromArgb(205, 212, 232));
            var f1 = new Font(pop, 30, FontStyle.Bold, GraphicsUnit.Pixel);
            var f2 = new Font(pop, 19, FontStyle.Bold, GraphicsUnit.Pixel);
            g.DrawString("Make Amiga games.", f1, Brushes.White, 34, 192, StringFormat.GenericTypographic);
            g.DrawString("No code needed.", f1, orange, 34, 230, StringFormat.GenericTypographic);
            g.DrawString("Real bootable disks for the", f2, dim, 36, 282, StringFormat.GenericTypographic);
            g.DrawString("Amiga 500, 600 and 1200", f2, dim, 36, 306, StringFormat.GenericTypographic);
            g.DrawImage(ball, 0, 0, 630, 500);
            g.Flush();
            bmp.Save(path, ImageFormat.Png);
        }
    }
}
"@
$ico = Join-Path $root "options\windows\icons\icon.ico"
$out = ""
if ($Png -ne "") { $out = [IO.Path]::GetFullPath($Png) }
[AdamArt]::WriteIco($ico, @(16, 20, 24, 32, 40, 48, 64, 128, 256), $out)
Write-Host "Wrote $ico"
$promo = Join-Path $root "promo"
if (-not (Test-Path $promo)) { New-Item -ItemType Directory $promo | Out-Null }
$cover = Join-Path $promo "itch_cover.png"
[AdamArt]::WriteCover($cover, (Join-Path $root "datafiles\fonts"))
Write-Host "Wrote $cover"
