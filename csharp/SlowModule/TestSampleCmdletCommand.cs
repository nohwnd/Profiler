using System.Management.Automation;

namespace SlowModule
{
    [Cmdlet(VerbsCommon.Get,"Factorial")]
    [OutputType(typeof(System.Numerics.BigInteger))]
    public class TestSampleCmdletCommand : PSCmdlet
    {
        [Parameter(
            Mandatory = true,
            Position = 0)]
        public int Number { get; set; }

        protected override void EndProcessing()
        {
            WriteObject(Factorial(Number));
        }

        public static System.Numerics.BigInteger Factorial(System.Numerics.BigInteger x)
        {
            System.Numerics.BigInteger res = x;
            x--;
            while (x > 1)
            {
                res *= x;
                x--;
            }
            return res;
        }
    }
}
