﻿using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Threading.Tasks;
using Microsoft.AspNetCore;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;

using Opserver.Helpers;
using Serilog;
using Serilog.Enrichers.Sensitive;
using Serilog.Exceptions;
namespace Opserver
{
    public static class Program
    {
        public static readonly DateTime StartDate = DateTime.UtcNow;

        private static async Task<int> Main(string[] args)
        {
            try
            {

                var host = WebHost.CreateDefaultBuilder(args)
                    .ConfigureAppConfiguration(
                        (_, config) =>
                        {
                            config
                                .AddJsonFile("appSettings.json", optional: true, reloadOnChange: true)
                                // v1.0 compat, for easier migrations
                                .AddPrefixedJsonFile("Security", "Config/SecuritySettings.json") // Note: manual migration from XML
                                .AddPrefixedJsonFile("Modules:Dashboard", "Config/DashboardSettings.json")
                                .AddPrefixedJsonFile("Modules:Cloudflare", "Config/CloudFlareSettings.json")
                                .AddPrefixedJsonFile("Modules:Elastic", "Config/ElasticSettings.json")
                                .AddPrefixedJsonFile("Modules:Exceptions", "Config/ExceptionsSettings.json")
                                .AddPrefixedJsonFile("Modules:HAProxy", "Config/HAProxySettings.json")
                                .AddPrefixedJsonFile("Modules:PagerDuty", "Config/PagerDutySettings.json")
                                .AddPrefixedJsonFile("Modules:Redis", "Config/RedisSettings.json")
                                .AddPrefixedJsonFile("Modules:SQL", "Config/SQLSettings.json")
                                // End compat
                                .AddJsonFile("Config/opserverSettings.json", optional: true, reloadOnChange: true)
                                .AddJsonFile("opserverSettings.json", optional: true, reloadOnChange: true)
                                .AddJsonFile("localSettings.json", optional: true, reloadOnChange: true)
                                .AddEnvironmentVariables();
                        }
                    )
                   .ConfigureLogging(
                    (hostingContext, config) =>
                    {
                        config.ClearProviders();

                        var dataDogServiceName = Environment.GetEnvironmentVariable("DD_SERVICE") ?? "opserver";
                        var product = hostingContext.Configuration.GetValue<string>("Product");
                        var tier = hostingContext.Configuration.GetValue<string>("Tier");

                        var loggerconfig = new LoggerConfiguration()
                            .ReadFrom.Configuration(hostingContext.Configuration)
                            .Enrich.FromLogContext()
                            .Enrich.WithEnvironmentUserName()
                            .Enrich.WithEnvironmentName()
                            .Enrich.WithProperty("dd_service", dataDogServiceName)
                            .Enrich.WithMachineName()
                            .Enrich.WithThreadId()
                            .Enrich.WithExceptionDetails()
                            .Enrich.WithSensitiveDataMasking(options =>
                            {
                                options.MaskingOperators = new List<IMaskingOperator>
                                {
                                    new EmailAddressMaskingOperator()
                                };
                            });

                        loggerconfig.Filter.ByExcluding("StartsWith(SourceContext, 'StackExchange.Exceptional.')");
                        loggerconfig.Filter.ByExcluding("SourceContext='Microsoft.AspNetCore.Diagnostics.ExceptionHandlerMiddleware' and @mt='An unhandled exception has occurred while executing the request.'");

                        Log.Logger = loggerconfig.CreateLogger();
                        config.AddSerilog(Log.Logger);
                    }
                )
                    .UseStartup<Startup>()
                    .Build();

                await host.RunAsync();
                return 0;
            }
            catch
            {
                return 1;
            }
            finally
            {
                if (Debugger.IsAttached)
                    Console.ReadKey();
            }
        }
    }
}
