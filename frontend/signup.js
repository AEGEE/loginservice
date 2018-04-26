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
                url: '/signup?token',
                params: {
                    token: null
                },
                data: {'pageTitle': 'Signing up to OMS'},
                views   : {
                    'main@': {
                        templateUrl: baseUrl + 'signup.html',
                        controller: 'CentralSignupController as vm'
                    }
                }
            });
    }

    function CentralSignupController($http, $state, $stateParams) {
        var vm = this;
        vm.campaign = "default"

        if($stateParams.token) {
            vm.showTokenArea = true;
            vm.token = $stateParams.token
        }

        vm.sendSignup = () => {
            vm.errors = {};

            if(vm.user.password != vm.user.password_copy) {
                vm.errors = {password: "Passwords don't match"}
                return;
            }
            if(!vm.terms) {
                vm.errors = {terms: "You must accept the terms and conditions to proceed"}
                return;
            }

            $http({
                url: apiUrl + '/campaigns/' + vm.campaign,
                method: 'POST',
                data: {submission: vm.user}
            }).then((res) => {
                vm.showTokenArea = true;
                showSuccess("You should receive a token in your email inbox soon")
            }).catch((error) => {
                if(error.status == 422)
                    vm.errors = error.data.errors;
                else
                    showError(error)
            })
        }

        vm.submitToken = () => {
            $http({
                url: apiUrl + '/confirm_mail/' + vm.token,
                method: 'POST'
            }).then((res) => {
                showSuccess("Congratulations, you can now login with your new username");
                $state.go("public.welcome");
            }).catch((error) => {
                showError(error);
            })
        }
    }

})();