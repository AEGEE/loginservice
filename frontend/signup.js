(function ()
{
    'use strict';

    const baseUrl = baseUrlRepository['oms-loginservice'];
    const apiUrl = `${baseUrl}api`;


    angular
        .module('public.signup', [])
        .config(config)
        .controller('CentralSignupController', CentralSignupController);

    /** @ngInject */
    function config($stateProvider)
    {
        // State
         $stateProvider
            .state('public.signup', {
                url: '/signup',
                data: {'pageTitle': 'Signing up to OMS'},
                views   : {
                    'main@': {
                        templateUrl: baseUrl + 'signup.html',
                        controller: 'CentralSignupController as vm'
                    }
                }
            });
    }

    function CentralSignupController() {
    }

})();