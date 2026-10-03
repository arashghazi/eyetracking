using System.Globalization;
using System.Numerics;

namespace EyeTracking.Domain;

/// <summary>Python's (and numpy's) numeric helpers where .NET differs in the last digit.</summary>
public static class PyMath
{
    /// <summary>Python's <c>round(x, ndigits)</c>: the exact binary value rounded half-to-even at
    /// <paramref name="digits"/> decimals, then read back as the nearest double. <c>Math.Round</c>
    /// scales first and can land on the other side of a midpoint.</summary>
    public static double Round(double x, int digits)
    {
        if (x == 0 || double.IsNaN(x) || double.IsInfinity(x))
            return x;
        var bits = BitConverter.DoubleToInt64Bits(x);
        var exponent = (int)((bits >> 52) & 0x7FF);
        var mantissa = bits & 0xFFFFFFFFFFFFFL;
        if (exponent == 0)
            exponent = 1;
        else
            mantissa |= 1L << 52;
        exponent -= 1075;

        // |x| * 10^digits = num / den exactly
        BigInteger num = mantissa, den = BigInteger.One;
        if (exponent > 0) num <<= exponent;
        else den <<= -exponent;
        if (digits >= 0) num *= BigInteger.Pow(10, digits);
        else den *= BigInteger.Pow(10, -digits);

        var q = BigInteger.DivRem(num, den, out var rem);
        var twice = rem * 2;
        if (twice > den || (twice == den && !q.IsEven))
            q += 1;
        var result = double.Parse($"{q}e{-digits}", NumberStyles.Float, CultureInfo.InvariantCulture);
        return bits < 0 ? -result : result;
    }

    /// <summary><c>statistics.median</c> and <c>np.median</c>: the middle value, or the mean of the two middle values.</summary>
    public static double Median(IEnumerable<double> values)
    {
        var sorted = values.Order().ToArray();
        if (sorted.Length == 0)
            throw new InvalidOperationException("no median for empty data");
        var mid = sorted.Length / 2;
        return sorted.Length % 2 == 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
    }

    /// <summary>Python 3.12's <c>sum()</c> of floats: Neumaier's compensated summation, so
    /// <c>sum([0.1] * 10)</c> is exactly 1.0 (a plain loop gives 0.9999999999999999).</summary>
    public static double Sum(IEnumerable<double> values)
    {
        double total = 0.0, c = 0.0;
        foreach (var x in values)
        {
            var t = total + x;
            c += Math.Abs(total) >= Math.Abs(x) ? (total - t) + x : (x - t) + total;
            total = t;
        }
        // as CPython: the compensation must not turn an infinite or overflowed sum into NaN
        return c != 0 && double.IsFinite(c) ? total + c : total;
    }

    /// <summary>Python's <c>math.hypot(x, y)</c> (CPython 3.12's vector_norm: lossless scaling and
    /// squaring, compensated sums, one correction step), so distances match to the last bit.</summary>
    public static double Hypot(double x, double y)
    {
        x = Math.Abs(x);
        y = Math.Abs(y);
        var max = 0.0;
        if (x > max) max = x;
        if (y > max) max = y;
        return VectorNorm([x, y], max, double.IsNaN(x) || double.IsNaN(y));
    }

    private static double VectorNorm(double[] vec, double max, bool foundNan)
    {
        if (double.IsInfinity(max))
            return max;
        if (foundNan)
            return double.NaN;
        if (max == 0.0 || vec.Length <= 1)
            return max;
        var maxE = Math.ILogB(max) + 1; // frexp's exponent
        if (maxE < -1023)
        {
            // ldexp(1.0, -max_e) would overflow: make subnormals normal first
            for (var i = 0; i < vec.Length; i++)
                vec[i] /= MinNormal;
            return MinNormal * VectorNorm(vec, max / MinNormal, foundNan);
        }
        var scale = Math.ScaleB(1.0, -maxE);
        double csum = 1.0, frac1 = 0.0, frac2 = 0.0;
        foreach (var v in vec)
        {
            var s = v * scale;
            var (prHi, prLo) = DlMul(s, s);
            var (smHi, smLo) = DlFastSum(csum, prHi);
            csum = smHi;
            frac1 += prLo;
            frac2 += smLo;
        }
        var h = Math.Sqrt(csum - 1.0 + (frac1 + frac2));
        var (hi, lo) = DlMul(-h, h);
        var (sumHi, sumLo) = DlFastSum(csum, hi);
        csum = sumHi;
        frac1 += lo;
        frac2 += sumLo;
        var correction = csum - 1.0 + (frac1 + frac2);
        h += correction / (2.0 * h);
        return h / scale;
    }

    private const double MinNormal = 2.2250738585072014e-308; // DBL_MIN

    private static (double Hi, double Lo) DlFastSum(double a, double b)
    {
        var x = a + b;
        return (x, (a - x) + b);
    }

    private static (double Hi, double Lo) DlMul(double x, double y)
    {
        var z = x * y;
        return (z, Math.FusedMultiplyAdd(x, y, -z));
    }

    /// <summary><c>np.percentile(values, q)</c> with numpy's default linear interpolation.</summary>
    public static double Percentile(IEnumerable<double> values, double q)
    {
        var sorted = values.Order().ToArray();
        var n = sorted.Length;
        if (n == 0)
            throw new InvalidOperationException("no percentile for empty data");
        var virtualIndex = (n - 1) * (q / 100);
        if (virtualIndex >= n - 1)
            return sorted[n - 1];
        var previous = Math.Floor(virtualIndex);
        var gamma = virtualIndex - previous;
        double a = sorted[(int)previous], b = sorted[(int)previous + 1];
        var diff = b - a;
        // numpy's _lerp interpolates from the nearer end
        return gamma >= 0.5 ? b - diff * (1 - gamma) : a + diff * gamma;
    }
}
