# Use the official Microsoft ASP.NET Core runtime image
# Adjust the version as necessary
FROM mcr.microsoft.com/dotnet/aspnet:6.0 AS base
WORKDIR /app
EXPOSE 5000
# ENV ASPNETCORE_URLS=http://+:5000


# Use SDK image to build the application
FROM mcr.microsoft.com/dotnet/sdk:6.0 AS build
WORKDIR /src
COPY ["Demo.CICD.csproj", "./"]
RUN dotnet restore "Demo.CICD.csproj"
COPY . .
WORKDIR "/src/"
RUN dotnet build "Demo.CICD.csproj" -c Release -o /app/build

FROM build AS publish
RUN dotnet publish "Demo.CICD.csproj" -c Release -o /app/publish

# Final stage/image
FROM base AS final
WORKDIR /app
COPY --from=publish /app/publish .
ENTRYPOINT ["dotnet", "Demo.CICD.dll"]
