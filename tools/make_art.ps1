# Draws ADAM's artwork from the title's boing ball and four Amiga stripes:
#   options/windows/icons/icon.ico   app icon (16-256 px)
#   promo/itch_cover.png             itch.io cover, 630 x 500
#   promo/itch_banner.png            itch.io page banner, 960 x 250
#   promo/itch_background.png        itch.io page background, 1920 x 1080 (soft slate, blurred balls)
#   options/windows/installer/header.bmp, finished.bmp   installer header 150 x 57, welcome/finish panel 164 x 314
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

    // ---------- installer (NSIS): welcome / finish panel 164 x 314 ----------
    const double WHor = 238;
    const double WBx = 82, WBy = 168, WBr = 50;

    static double[] PanelBack(double u, double v)
    {
        double[] c = { 0, 0, 0, 1 };
        double t = Math.Min(1, v / WHor);
        double band = Math.Floor(t * 12) / 12;
        c[0] = (14 + 70 * band) / 255; c[1] = (18 + 16 * band) / 255; c[2] = (48 + 70 * band) / 255;
        if (v >= WHor)
        {
            double dv = v - WHor + 0.5;
            double fz = (v - WHor) / (314 - WHor);
            c[0] = (34 + 26 * fz) / 255; c[1] = (22 + 12 * fz) / 255; c[2] = (56 + 30 * fz) / 255;
            double gx = (u - 82) * 1.6 / dv, gz = 380 / dv;
            double ppx = dv / 1.6, ppz = dv * dv / 380;
            double ex = Math.Abs(gx - Math.Round(gx)) * ppx, ez = Math.Abs(gz - Math.Round(gz)) * ppz;
            double line = 0;
            if (ex < 0.9) { line = Math.Min(1, ppx / 4); }
            if (ez < 0.9) { line = Math.Max(line, Math.Min(1, (ppz - 1.5) / 5)); }
            if (line > 0) { Mix(c, 175 / 255.0, 95 / 255.0, 235 / 255.0, 0.9 * line); }
            if (v < WHor + 1.2) { Mix(c, 1, 0.75, 0.95, 0.6); }
        }
        double sx = (u - WBx - 12) / 52, sy = (v - 262) / 9;
        double e = sx * sx + sy * sy;
        if (e < 1) { Mix(c, 0, 0, 0, 0.6 * (1 - e)); }
        return c;
    }

    static double[] PanelBall(double u, double v)
    {
        double[] c = { 0, 0, 0, 0 };
        Ball(c, u, v, WBx, WBy, WBr);
        return c;
    }

    // ---------- installer header 150 x 57: the title badge ----------
    static double[] HeaderBack(double u, double v)
    {
        double[] c = { 1, 1, 1, 1 };
        double m = 4, rad = 24.5;
        double qx = Math.Max(Math.Abs(u - 75) - (75 - m - rad), 0);
        double qy = Math.Max(Math.Abs(v - 28.5) - (28.5 - m - rad), 0);
        if (Math.Sqrt(qx * qx + qy * qy) > rad) { return c; }
        double t = (v - m) / (57 - 2 * m);
        c[0] = (68 + (38 - 68) * t) / 255; c[1] = (79 + (45 - 79) * t) / 255; c[2] = (96 + (57 - 96) * t) / 255;
        if (v < 26) { Mix(c, 1, 1, 1, 0.06); }
        Ball(c, u, v, 28, 28.5, 18);
        return c;
    }

    static void DrawTitle(Graphics g, FontFamily pop, string text, float size, float x, float y, float stripeW, float stripeGap, bool shadow)
    {
        var title = new GraphicsPath();
        title.AddString(text, pop, (int)FontStyle.Bold, size, new PointF(x, y), StringFormat.GenericTypographic);
        if (shadow)
        {
            using (var sh = (GraphicsPath)title.Clone())
            {
                var mtx = new Matrix(); mtx.Translate(size * 0.04f, size * 0.06f); sh.Transform(mtx);
                g.FillPath(new SolidBrush(Color.FromArgb(120, 0, 0, 0)), sh);
            }
        }
        RectangleF tb = title.GetBounds();
        g.FillPath(new LinearGradientBrush(new PointF(0, tb.Top), new PointF(0, tb.Bottom + 1), Color.White, Color.FromArgb(205, 212, 232)), title);
        int[][] sc = { new[] {230, 60, 50}, new[] {250, 160, 40}, new[] {90, 190, 90}, new[] {60, 130, 230} };
        float sx = tb.Right + stripeGap, sb = tb.Bottom, st = tb.Top + 1, lean = (sb - st) * 0.42f;
        for (int i = 0; i < 4; i++)
        {
            float o = sx + i * stripeW * 1.36f;
            g.FillPolygon(new SolidBrush(Color.FromArgb(sc[i][0], sc[i][1], sc[i][2])),
                new[] { new PointF(o, sb), new PointF(o + stripeW, sb), new PointF(o + stripeW + lean, st), new PointF(o + lean, st) });
        }
    }

    static void SaveBmp24(Bitmap src, string path)
    {
        using (var b24 = new Bitmap(src.Width, src.Height, PixelFormat.Format24bppRgb))
        using (var g = Graphics.FromImage(b24))
        {
            g.Clear(Color.White);
            g.DrawImage(src, 0, 0, src.Width, src.Height);
            b24.Save(path, ImageFormat.Bmp);
        }
    }

    public static void WriteInstaller(string headerPath, string finishedPath, string fontDir)
    {
        using (var fonts = new PrivateFontCollection())
        {
            fonts.AddFontFile(Path.Combine(fontDir, "Poppins-Bold.ttf"));
            FontFamily pop = fonts.Families[0];

            using (var bmp = Render(150, 57, 1.0, HeaderBack, 4))
            using (var g = Graphics.FromImage(bmp))
            {
                g.SmoothingMode = SmoothingMode.AntiAlias;
                g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
                g.PixelOffsetMode = PixelOffsetMode.HighQuality;
                DrawTitle(g, pop, "ADAM", 21, 52, 17, 3.0f, 4, false);
                g.Flush();
                SaveBmp24(bmp, headerPath);
            }

            using (var bmp = Render(164, 314, 1.0, PanelBack, 4))
            using (var ball = Render(164, 314, 1.0, PanelBall, 4))
            using (var g = Graphics.FromImage(bmp))
            {
                g.SmoothingMode = SmoothingMode.AntiAlias;
                g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
                g.PixelOffsetMode = PixelOffsetMode.HighQuality;
                DrawTitle(g, pop, "ADAM", 33, 14, 24, 4.6f, 6, true);
                var orange = new SolidBrush(Color.FromArgb(255, 150, 40));
                var f1 = new Font(pop, 13, FontStyle.Bold, GraphicsUnit.Pixel);
                g.DrawString("Make Amiga games.", f1, Brushes.White, 16, 80, StringFormat.GenericTypographic);
                g.DrawString("No code needed.", f1, orange, 16, 98, StringFormat.GenericTypographic);
                g.DrawImage(ball, 0, 0, 164, 314);
                g.Flush();
                SaveBmp24(bmp, finishedPath);
            }
        }
    }

    // ---------- itch.io banner 960 x 250 ----------
    const double BHor = 182;
    const double BBx = 826, BBy = 112, BBr = 86;

    static double[] BannerBack(double u, double v)
    {
        double[] c = { 0, 0, 0, 1 };
        double t = Math.Min(1, v / BHor);
        double band = Math.Floor(t * 12) / 12;
        c[0] = (14 + 70 * band) / 255; c[1] = (18 + 16 * band) / 255; c[2] = (48 + 70 * band) / 255;
        if (v >= BHor)
        {
            double dv = v - BHor + 0.5;
            double fz = (v - BHor) / (250 - BHor);
            c[0] = (34 + 26 * fz) / 255; c[1] = (22 + 12 * fz) / 255; c[2] = (56 + 30 * fz) / 255;
            double gx = (u - 700) * 2.0 / dv, gz = 500 / dv;
            double ppx = dv / 2.0, ppz = dv * dv / 500;
            double ex = Math.Abs(gx - Math.Round(gx)) * ppx, ez = Math.Abs(gz - Math.Round(gz)) * ppz;
            double line = 0;
            if (ex < 1.0) { line = Math.Min(1, ppx / 4); }
            if (ez < 1.0) { line = Math.Max(line, Math.Min(1, (ppz - 1.5) / 5)); }
            if (line > 0) { Mix(c, 175 / 255.0, 95 / 255.0, 235 / 255.0, 0.9 * line); }
            if (v < BHor + 1.5) { Mix(c, 1, 0.75, 0.95, 0.6); }
        }
        double sx = (u - BBx - 22) / 92, sy = (v - 222) / 13;
        double e = sx * sx + sy * sy;
        if (e < 1) { Mix(c, 0, 0, 0, 0.6 * (1 - e)); }
        return c;
    }

    static double[] BannerBall(double u, double v)
    {
        double[] c = { 0, 0, 0, 0 };
        Ball(c, u, v, BBx, BBy, BBr);
        return c;
    }

    public static void WriteBanner(string path, string fontDir)
    {
        using (var bmp = Render(960, 250, 1.0, BannerBack, 3))
        using (var ball = Render(960, 250, 1.0, BannerBall, 4))
        using (var g = Graphics.FromImage(bmp))
        using (var fonts = new PrivateFontCollection())
        {
            fonts.AddFontFile(Path.Combine(fontDir, "Poppins-Bold.ttf"));
            FontFamily pop = fonts.Families[0];
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
            g.PixelOffsetMode = PixelOffsetMode.HighQuality;
            DrawTitle(g, pop, "ADAM", 96, 40, 34, 10, 14, true);
            var orange = new SolidBrush(Color.FromArgb(255, 150, 40));
            var dim = new SolidBrush(Color.FromArgb(205, 212, 232));
            var f1 = new Font(pop, 30, FontStyle.Bold, GraphicsUnit.Pixel);
            var f2 = new Font(pop, 17, FontStyle.Bold, GraphicsUnit.Pixel);
            g.DrawString("Make Amiga games.", f1, Brushes.White, 44, 150, StringFormat.GenericTypographic);
            float w1 = g.MeasureString("Make Amiga games.", f1, 2000, StringFormat.GenericTypographic).Width;
            g.DrawString("No code needed.", f1, orange, 44 + w1 + 12, 150, StringFormat.GenericTypographic);
            g.DrawString("Bootable disks for the Amiga 500, 600 and 1200", f2, dim, 46, 196, StringFormat.GenericTypographic);
            g.DrawImage(ball, 0, 0, 960, 250);
            g.Flush();
            bmp.Save(path, ImageFormat.Png);
        }
    }

    // ---------- itch.io page background 1920 x 1080: soft slate, blurred balls ----------
    static double[] AmbientSample(double u, double v)
    {
        // u, v in a 480 x 270 space; the picture is drawn small and scaled up, which blurs it
        double[] c = { 0, 0, 0, 1 };
        double t = v / 270;
        c[0] = (62 - 26 * t) / 255; c[1] = (70 - 28 * t) / 255; c[2] = (82 - 30 * t) / 255;
        double vx = (u - 240) / 300, vy = (v - 120) / 220;          // gentle light in the middle
        Mix(c, 92 / 255.0, 102 / 255.0, 118 / 255.0, Math.Max(0, 0.45 - (vx * vx + vy * vy) * 0.5));
        double[][] balls = { new double[] {64, 150, 46, 0.30}, new double[] {420, 205, 58, 0.26}, new double[] {388, 52, 20, 0.22}, new double[] {120, 228, 26, 0.20} };
        foreach (var b in balls)
        {
            double[] bc = { 0, 0, 0, 0 };
            if (Ball(bc, u, v, b[0], b[1], b[2])) { Mix(c, bc[0], bc[1], bc[2], b[3]); }
        }
        return c;
    }

    public static void WriteBackground(string path, string fontDir)
    {
        using (var small = Render(480, 270, 1.0, AmbientSample, 3))
        using (var bmp = new Bitmap(1920, 1080, PixelFormat.Format32bppArgb))
        using (var g = Graphics.FromImage(bmp))
        using (var fonts = new PrivateFontCollection())
        {
            g.InterpolationMode = InterpolationMode.HighQualityBicubic;
            g.PixelOffsetMode = PixelOffsetMode.HighQuality;
            using (var mid = new Bitmap(small, 120, 68)) { g.DrawImage(mid, -8, -8, 1936, 1096); }   // extra blur
            using (var wash = new Bitmap(small)) { var ia = new ImageAttributes(); var cm = new ColorMatrix(); cm.Matrix33 = 0.55f; ia.SetColorMatrix(cm); g.DrawImage(wash, new Rectangle(0, 0, 1920, 1080), 0, 0, 480, 270, GraphicsUnit.Pixel, ia); }
            // a faint ADAM logo, blurred the same way
            fonts.AddFontFile(Path.Combine(fontDir, "Poppins-Bold.ttf"));
            using (var logo = new Bitmap(480, 270, PixelFormat.Format32bppArgb))
            using (var lg = Graphics.FromImage(logo))
            {
                lg.SmoothingMode = SmoothingMode.AntiAlias;
                lg.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
                DrawTitle(lg, fonts.Families[0], "ADAM", 30, 16, 12, 3.3f, 5, false);
                var ia = new ImageAttributes(); var cm = new ColorMatrix(); cm.Matrix33 = 0.16f; ia.SetColorMatrix(cm);
                g.DrawImage(logo, new Rectangle(0, 0, 1920, 1080), 0, 0, 480, 270, GraphicsUnit.Pixel, ia);
            }
            // fine noise so the gradient does not band
            var rnd = new Random(1985);
            for (int i = 0; i < 60000; i++)
            {
                int px = rnd.Next(1920), py = rnd.Next(1080);
                Color o = bmp.GetPixel(px, py);
                int d = rnd.Next(-4, 5);
                bmp.SetPixel(px, py, Color.FromArgb(255, Math.Max(0, Math.Min(255, o.R + d)), Math.Max(0, Math.Min(255, o.G + d)), Math.Max(0, Math.Min(255, o.B + d))));
            }
            bmp.Save(path, ImageFormat.Png);
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
[AdamArt]::WriteBanner((Join-Path $promo "itch_banner.png"), (Join-Path $root "datafiles\fonts"))
[AdamArt]::WriteBackground((Join-Path $promo "itch_background.png"), (Join-Path $root "datafiles\fonts"))
Write-Host "Wrote $promo\itch_banner.png and itch_background.png"
$inst = Join-Path $root "options\windows\installer"
[AdamArt]::WriteInstaller((Join-Path $inst "header.bmp"), (Join-Path $inst "finished.bmp"), (Join-Path $root "datafiles\fonts"))
Write-Host "Wrote $inst\header.bmp and finished.bmp"
