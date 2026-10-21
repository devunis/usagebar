using System;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Xml.Linq;
using UsageBar.Core;

namespace UsageBar.Windows;

internal static class Theme
{
    public static readonly Brush Background = Brush("#10151E");
    public static readonly Brush Card = Brush("#1B2330");
    public static readonly Brush Muted = Brush("#9CAEC5");
    public static readonly Brush Accent = Brush("#50D4AE");
    public static Brush Brush(string color) => new SolidColorBrush((Color)ColorConverter.ConvertFromString(color));
    public static Brush ProviderBrush(Provider provider) => provider == Provider.Codex ? Accent : Brush("#E69B71");

    public static void Install(Application app)
    {
        var text = new Style(typeof(TextBlock));
        // Do not force white on implicit TextBlocks: button/ComboBox content must
        // inherit its control's dark foreground on the native light surface.
        text.Setters.Add(new Setter(TextBlock.TextWrappingProperty, TextWrapping.Wrap));
        app.Resources[typeof(TextBlock)] = text;
        var button = new Style(typeof(Button));
        button.Setters.Add(new Setter(Control.PaddingProperty, new Thickness(12, 7, 12, 7)));
        button.Setters.Add(new Setter(Control.MarginProperty, new Thickness(0, 0, 8, 0)));
        button.Setters.Add(new Setter(Control.BackgroundProperty, Brush("#E2EAF3")));
        button.Setters.Add(new Setter(Control.ForegroundProperty, Brushes.Black));
        app.Resources[typeof(Button)] = button;
        var check = new Style(typeof(CheckBox));
        check.Setters.Add(new Setter(Control.ForegroundProperty, Brushes.White));
        check.Setters.Add(new Setter(Control.MarginProperty, new Thickness(0, 8, 0, 8)));
        app.Resources[typeof(CheckBox)] = check;
    }

    public static BitmapImage AppIcon() => new(new Uri("pack://application:,,,/Assets/AppIcon.png"));

    public static ImageSource Brand(Provider provider)
    {
        var file = provider == Provider.Codex ? "openai" : "claude";
        using var stream = Application.GetResourceStream(new Uri($"pack://application:,,,/Assets/{file}.svg"))?.Stream
            ?? throw new IOException("Brand resource missing");
        var document = XDocument.Load(stream);
        var drawing = new DrawingGroup();
        foreach (var path in document.Descendants().Where(element => element.Name.LocalName == "path"))
        {
            var data = path.Attribute("d")?.Value ?? "";
            // Both bundled marks use SVG path syntax supported by WPF's mini-language.
            var geometry = Geometry.Parse((provider == Provider.Codex ? "F0 " : "F1 ") + data);
            drawing.Children.Add(new GeometryDrawing(provider == Provider.Codex ? Brushes.White : ProviderBrush(provider), null, geometry));
        }
        drawing.Freeze();
        return new DrawingImage(drawing);
    }
}
